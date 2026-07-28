import Combine
import UIKit
import AICreditsCore

/// Pay Day Pro paywall. Sells the compliance wedge with the post-3.1.2 pattern:
/// three selectable plan cards where the billed price + full term dominate, a
/// trial badged on the annual card only (no toggle), a single dynamic CTA, and
/// Terms/Privacy/Restore in the first screenful. Real prices come from the
/// AICredits store; a DEBUG fallback renders the decided prices so the page is
/// complete for screenshots before StoreKit products resolve.
final class PaywallViewController: UIViewController {
    private struct PlanVM {
        let id: String
        let title: String
        let price: String
        let term: String
        let badge: String?
        let footnote: String?
        let cta: String
    }

    private let reason: String
    private let store = AICreditsManager.store
    private var cancellables = Set<AnyCancellable>()
    private let cardsStack = UIStackView()
    private let ctaButton = DesignSystem.primaryButton(String(localized: "Continue"))
    private var plans: [PlanVM] = []
    private var selectedIndex = 0
    private var cardViews: [UIControl] = []

    init(reason: String = String(localized: "Unlock compliant e-invoicing and Peppol delivery.")) {
        self.reason = reason
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        title = String(localized: "Pay Day Pro")
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: String(localized: "Restore"), primaryAction: UIAction { [weak self] _ in self?.restore() })
        build()
        bindStore()
        // Never show fabricated prices in release — they could drift from App
        // Store Connect (3.1.2). DEBUG renders decided prices for screenshots;
        // release shows a loading state until the store's real plans arrive.
        #if DEBUG
        plans = Self.fallbackPlans
        #endif
        renderCards()
        Task { await loadPlans() }
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.plans.isEmpty else { return }
                Task { await self.loadPlans() }
            }
            .store(in: &cancellables)
    }

    private func loadPlans() async {
        if plans.isEmpty { renderCards() }
        await store.loadPlans()
        if store.plans.isEmpty && plans.isEmpty { renderPlansLoadFailure() }
    }

    private func renderPlansLoadFailure() {
        cardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        cardViews = []
        let message = DesignSystem.label(
            String(localized: "Couldn't load plans. Check your connection."),
            font: DesignSystem.Typography.body(),
            color: DesignSystem.Color.secondary)
        let retry = UIButton(type: .system)
        retry.setTitle(String(localized: "Try Again"), for: .normal)
        retry.titleLabel?.font = DesignSystem.Typography.scaledSystem(15, .semibold, relativeTo: .callout)
        retry.titleLabel?.adjustsFontForContentSizeCategory = true
        retry.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Task { await self.loadPlans() }
        }, for: .touchUpInside)
        cardsStack.addArrangedSubview(message)
        cardsStack.addArrangedSubview(retry)
    }

    private func build() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.l
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = DesignSystem.label(String(localized: "Get paid, compliantly."), font: DesignSystem.Typography.largeTitle())
        let subtitle = DesignSystem.label(reason, font: DesignSystem.Typography.body(), color: DesignSystem.Color.secondary)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)

        cardsStack.axis = .vertical
        cardsStack.spacing = DesignSystem.Spacing.s
        stack.addArrangedSubview(cardsStack)

        for (symbol, label, detail) in [
            ("checkmark.seal.fill",
             String(localized: "EN 16931 e-invoices"),
             String(localized: "Factur-X / ZUGFeRD PDFs that pass tax-authority validation.")),
            ("paperplane.fill",
             String(localized: "Peppol delivery"),
             String(localized: "Send straight into your client's accounting system.")),
            ("arrow.triangle.2.circlepath",
             String(localized: "Recurring invoices"),
             String(localized: "Set it once, get paid every month.")),
            ("paintbrush.fill",
             String(localized: "Your branding"),
             String(localized: "Logo, accent colour, custom templates.")),
            ("checkmark.circle.fill",
             String(localized: "VAT validation"),
             String(localized: "Live VIES checks on every client.")),
        ] {
            stack.addArrangedSubview(benefitRow(symbol: symbol, title: label, detail: detail))
        }

        ctaButton.addAction(UIAction { [weak self] _ in self?.purchaseSelected() }, for: .touchUpInside)
        stack.addArrangedSubview(ctaButton)
        stack.addArrangedSubview(autoRenewDisclosure())
        stack.addArrangedSubview(legalFooter())

        view.addSubview(scroll)
        scroll.addSubview(stack)
        scroll.pinEdges(toSafeAreaOf: view)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: DesignSystem.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: DesignSystem.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -DesignSystem.Spacing.m),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -DesignSystem.Spacing.l),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -DesignSystem.Spacing.m * 2),
        ])
    }

    private func bindStore() {
        store.$plans
            .receive(on: DispatchQueue.main)
            .sink { [weak self] storePlans in
                guard let self, !storePlans.isEmpty else { return }
                self.plans = storePlans.map(Self.map)
                self.selectedIndex = self.plans.firstIndex { $0.id.contains("annual") } ?? 0
                self.renderCards()
            }
            .store(in: &cancellables)
        // dropFirst: $isPremium replays its current value on subscribe, so without
        // this an already-Pro user opening the paywall (e.g. Settings → Credits)
        // would have it dismiss instantly. Only a transition to Pro should close it.
        store.$isPremium
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPremium in if isPremium { self?.dismiss(animated: true) } }
            .store(in: &cancellables)
        store.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] error in
                guard let self, self.presentedViewController == nil else { return }
                self.presentAlert(String(localized: "Purchase Failed"), message: error.localizedDescription)
                self.store.error = nil
            }
            .store(in: &cancellables)
    }

    private func renderCards() {
        cardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        cardViews = []
        guard !plans.isEmpty else {
            let loading = DesignSystem.label(String(localized: "Loading plans…"), font: DesignSystem.Typography.body(), color: DesignSystem.Color.secondary)
            cardsStack.addArrangedSubview(loading)
            ctaButton.isEnabled = false
            ctaButton.alpha = 0.5
            return
        }
        ctaButton.isEnabled = true
        ctaButton.alpha = 1
        for (index, plan) in plans.enumerated() {
            let card = planCard(plan, selected: index == selectedIndex)
            card.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .touchUpInside)
            cardsStack.addArrangedSubview(card)
            cardViews.append(card)
        }
        updateCTA()
    }

    private func select(_ index: Int) {
        guard index != selectedIndex else { return }
        Haptics.selection()
        selectedIndex = index
        UIView.transition(with: cardsStack, duration: 0.2, options: .transitionCrossDissolve) {
            self.renderCards()
        }
    }

    private func updateCTA() {
        guard plans.indices.contains(selectedIndex) else { return }
        ctaButton.configuration?.attributedTitle = AttributedString(
            plans[selectedIndex].cta,
            attributes: AttributeContainer([.font: DesignSystem.Typography.scaledSystem(17, .semibold)]))
    }

    private func planCard(_ plan: PlanVM, selected: Bool) -> UIControl {
        let card = UIControl()
        card.backgroundColor = DesignSystem.Color.surface
        card.layer.cornerRadius = DesignSystem.Radius.card
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = selected ? 2 : 1
        let borderColor = selected ? DesignSystem.Color.accent : DesignSystem.Color.separator
        card.layer.borderColor = borderColor.resolvedColor(with: card.traitCollection).cgColor
        card.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (card: UIControl, _) in
            card.layer.borderColor = borderColor.resolvedColor(with: card.traitCollection).cgColor
        }

        let priceLabel = DesignSystem.label(
            String(localized: "\(plan.price) / \(plan.term)",
                   comment: "Plan card headline: localized price then the billing term, e.g. €39.99 / year"),
            font: DesignSystem.Typography.scaledSystem(20, .bold, relativeTo: .title3))
        let titleLabel = DesignSystem.label(plan.title, font: DesignSystem.Typography.scaledSystem(13, .medium, relativeTo: .footnote), color: DesignSystem.Color.secondary)
        let left = UIStackView(arrangedSubviews: [priceLabel, titleLabel])
        left.axis = .vertical
        left.spacing = 2

        let right = UIStackView()
        right.axis = .vertical
        right.alignment = .trailing
        right.spacing = 4
        if let badge = plan.badge {
            right.addArrangedSubview(DesignSystem.statusPill("paid", title: badge))
        }
        let check = UIImageView(image: UIImage(systemName: selected ? "checkmark.circle.fill" : "circle"))
        check.tintColor = selected ? DesignSystem.Color.accent : DesignSystem.Color.tertiary
        right.addArrangedSubview(check)

        let row = UIStackView(arrangedSubviews: [left, right])
        row.axis = .horizontal
        row.alignment = .center
        let column = UIStackView(arrangedSubviews: [row])
        column.axis = .vertical
        column.spacing = 4
        if let footnote = plan.footnote {
            column.addArrangedSubview(DesignSystem.label(
                footnote,
                font: DesignSystem.Typography.scaledSystem(11, .regular, relativeTo: .caption2),
                color: DesignSystem.Color.secondary))
        }
        column.translatesAutoresizingMaskIntoConstraints = false
        column.isUserInteractionEnabled = false
        card.addSubview(column)
        column.pinEdges(to: card, insets: UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))

        card.isAccessibilityElement = true
        card.accessibilityTraits = selected ? [.button, .selected] : [.button]
        card.accessibilityLabel = accessibilityLabel(for: plan)
        return card
    }

    private func accessibilityLabel(for plan: PlanVM) -> String {
        var parts = [String(localized: "\(plan.title), \(plan.price) per \(plan.term)",
                            comment: "VoiceOver label for a plan card: plan title, price, billing term")]
        if let footnote = plan.footnote { parts.append(footnote) }
        return parts.joined(separator: ". ")
    }

    private func autoRenewDisclosure() -> UIView {
        let disclosure = DesignSystem.label(
            String(localized: "Subscriptions auto-renew unless cancelled at least 24h before the period ends. Manage in Apple ID settings."),
            font: DesignSystem.Typography.scaledSystem(11, .regular, relativeTo: .caption2),
            color: DesignSystem.Color.tertiary)
        disclosure.textAlignment = .center
        return disclosure
    }

    private func legalFooter() -> UIView {
        let links = UIStackView()
        links.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        links.spacing = 16
        links.alignment = .center
        links.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (links: UIStackView, _) in
            links.axis = links.traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        }
        for (title, url) in [(String(localized: "Terms of Use"), "https://mako.midgarcorp.cc/terms/payday"),
                             (String(localized: "Privacy Policy"), "https://mako.midgarcorp.cc/privacy/payday"),
                             (String(localized: "Restore"), "")] {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = DesignSystem.Typography.scaledSystem(11, .medium, relativeTo: .caption2)
            b.titleLabel?.adjustsFontForContentSizeCategory = true
            b.addAction(UIAction { [weak self] _ in
                if url.isEmpty { self?.restore() }
                else if let u = URL(string: url) { self?.openLink(u) }
            }, for: .touchUpInside)
            links.addArrangedSubview(b)
        }
        return links
    }

    private func openLink(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard !success else { return }
            self?.presentAlert(String(localized: "Couldn't open the link"), message: String(localized: "Please try again in a moment."))
        }
    }

    private func purchaseSelected() {
        guard plans.indices.contains(selectedIndex) else { return }
        let id = plans[selectedIndex].id
        guard let plan = store.plans.first(where: { $0.id == id }) else {
            presentAlert(String(localized: "Plans are still loading"), message: String(localized: "Try again in a moment."))
            return
        }
        setPurchasing(true)
        Task { [weak self] in
            _ = await self?.store.subscribe(plan)
            self?.setPurchasing(false)
        }
    }

    private func setPurchasing(_ purchasing: Bool) {
        ctaButton.isEnabled = !purchasing && !plans.isEmpty
        ctaButton.configuration?.showsActivityIndicator = purchasing
        cardViews.forEach { $0.isEnabled = !purchasing }
    }

    private func presentAlert(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private func restore() {
        setPurchasing(true)
        Task { [weak self] in
            guard let self else { return }
            await self.store.restore()
            self.setPurchasing(false)
            if !self.store.isPremium && self.store.error == nil {
                self.presentAlert(
                    String(localized: "No Purchases to Restore"),
                    message: String(localized: "No active Pay Day Pro subscription was found for this Apple ID."))
            }
        }
    }

    private func benefitRow(symbol: String, title: String, detail: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let titleLabel = DesignSystem.label(title, font: DesignSystem.Typography.scaledSystem(16, .semibold, relativeTo: .callout))
        let detailLabel = DesignSystem.label(detail, font: DesignSystem.Typography.caption(), color: DesignSystem.Color.secondary)
        let text = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 2
        let row = UIStackView(arrangedSubviews: [icon, text])
        row.axis = .horizontal
        row.spacing = DesignSystem.Spacing.m
        row.alignment = .top
        return row
    }

    private static func map(_ plan: SubscriptionPlan) -> PlanVM {
        let term: String
        switch plan.period {
        case .annual: term = String(localized: "year", comment: "Billing term shown after a price, e.g. €39.99 / year")
        case .monthly: term = String(localized: "month", comment: "Billing term shown after a price, e.g. €4.99 / month")
        case .weekly: term = String(localized: "week", comment: "Billing term shown after a price, e.g. €1.99 / week")
        }
        let trial = (plan.trialEligible && (plan.trialDays ?? 0) > 0)
            ? String(localized: "\(plan.trialDays!) days free, then \(plan.localizedPrice)/\(term). Auto-renews. Cancel anytime.")
            : nil
        return PlanVM(id: plan.id, title: planTitle(plan.period), price: plan.localizedPrice, term: term,
                      badge: plan.period == .annual ? String(localized: "Save 33%") : nil, footnote: trial,
                      cta: plan.period == .annual && trial != nil
                          ? String(localized: "Start \(plan.trialDays ?? 7)-day free trial")
                          : String(localized: "Subscribe"))
    }

    private static func planTitle(_ period: SubscriptionPlan.Period) -> String {
        switch period {
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Billed monthly")
        case .annual: return String(localized: "Billed annually")
        }
    }

    private static let fallbackPlans: [PlanVM] = [
        PlanVM(id: "com.guitaripod.payday.pro.annual", title: "Billed annually", price: "€39.99", term: "year",
               badge: "Save 33%", footnote: "7 days free, then €39.99/year. Auto-renews. Cancel anytime.",
               cta: "Start 7-day free trial"),
        PlanVM(id: "com.guitaripod.payday.pro.monthly", title: "Billed monthly", price: "€4.99", term: "month",
               badge: nil, footnote: "Billed €4.99 every month. Auto-renews. Cancel anytime.", cta: "Subscribe"),
    ]
}

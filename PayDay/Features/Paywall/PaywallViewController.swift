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
    private let ctaButton = DesignSystem.primaryButton("Continue")
    private var plans: [PlanVM] = []
    private var selectedIndex = 0
    private var cardViews: [UIControl] = []

    init(reason: String = "Unlock compliant e-invoicing and Peppol delivery.") {
        self.reason = reason
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        title = "Pay Day Pro"
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Restore", primaryAction: UIAction { [weak self] _ in self?.restore() })
        build()
        bindStore()
        plans = Self.fallbackPlans
        renderCards()
        Task { await store.loadPlans() }
    }

    private func build() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.l
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = DesignSystem.label("Get paid, compliantly.", font: DesignSystem.Typography.largeTitle())
        let subtitle = DesignSystem.label(reason, font: DesignSystem.Typography.body(), color: DesignSystem.Color.secondary)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)

        for (symbol, label, detail) in [
            ("checkmark.seal.fill", "EN 16931 e-invoices", "Factur-X / ZUGFeRD PDFs that pass tax-authority validation."),
            ("paperplane.fill", "Peppol delivery", "Send straight into your client's accounting system."),
            ("arrow.triangle.2.circlepath", "Recurring invoices", "Set it once, get paid every month."),
            ("paintbrush.fill", "Your branding", "Logo, accent colour, custom templates."),
            ("checkmark.circle.fill", "VAT validation", "Live VIES checks on every client."),
        ] {
            stack.addArrangedSubview(benefitRow(symbol: symbol, title: label, detail: detail))
        }

        cardsStack.axis = .vertical
        cardsStack.spacing = DesignSystem.Spacing.s
        stack.addArrangedSubview(cardsStack)

        ctaButton.addAction(UIAction { [weak self] _ in self?.purchaseSelected() }, for: .touchUpInside)
        stack.addArrangedSubview(ctaButton)
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
    }

    private func renderCards() {
        cardsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        cardViews = []
        for (index, plan) in plans.enumerated() {
            let card = planCard(plan, selected: index == selectedIndex)
            card.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .touchUpInside)
            cardsStack.addArrangedSubview(card)
            cardViews.append(card)
        }
        updateCTA()
    }

    private func select(_ index: Int) {
        selectedIndex = index
        renderCards()
    }

    private func updateCTA() {
        guard plans.indices.contains(selectedIndex) else { return }
        ctaButton.configuration?.attributedTitle = AttributedString(
            plans[selectedIndex].cta,
            attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
    }

    private func planCard(_ plan: PlanVM, selected: Bool) -> UIControl {
        let card = UIControl()
        card.backgroundColor = DesignSystem.Color.surface
        card.layer.cornerRadius = DesignSystem.Radius.card
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = selected ? 2 : 1
        card.layer.borderColor = (selected ? DesignSystem.Color.accent : DesignSystem.Color.separator).cgColor

        let priceLabel = DesignSystem.label("\(plan.price) / \(plan.term)", font: .systemFont(ofSize: 20, weight: .bold))
        let titleLabel = DesignSystem.label(plan.title, font: .systemFont(ofSize: 13, weight: .medium), color: DesignSystem.Color.secondary)
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
            column.addArrangedSubview(DesignSystem.label(footnote, font: .systemFont(ofSize: 11), color: DesignSystem.Color.secondary))
        }
        column.translatesAutoresizingMaskIntoConstraints = false
        column.isUserInteractionEnabled = false
        card.addSubview(column)
        column.pinEdges(to: card, insets: UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16))
        return card
    }

    private func legalFooter() -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        let disclosure = DesignSystem.label(
            "Subscriptions auto-renew unless cancelled at least 24h before the period ends. Manage in Apple ID settings.",
            font: .systemFont(ofSize: 10), color: DesignSystem.Color.tertiary)
        disclosure.textAlignment = .center
        let links = UIStackView()
        links.axis = .horizontal
        links.spacing = 16
        for (title, url) in [("Terms of Use", "https://mako.midgarcorp.cc/terms/payday"),
                             ("Privacy Policy", "https://mako.midgarcorp.cc/privacy/payday"),
                             ("Restore", "")] {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
            b.addAction(UIAction { [weak self] _ in
                if url.isEmpty { self?.restore() }
                else if let u = URL(string: url) { UIApplication.shared.open(u) }
            }, for: .touchUpInside)
            links.addArrangedSubview(b)
        }
        stack.addArrangedSubview(disclosure)
        stack.addArrangedSubview(links)
        return stack
    }

    private func purchaseSelected() {
        guard plans.indices.contains(selectedIndex) else { return }
        let id = plans[selectedIndex].id
        Task {
            let storePlans = store.plans
            guard let plan = storePlans.first(where: { $0.id == id }) else {
                // Test-store / pre-products fallback: nothing to purchase yet.
                return
            }
            _ = await store.subscribe(plan)
        }
    }

    private func restore() {
        Task { await store.restore() }
    }

    private func benefitRow(symbol: String, title: String, detail: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let titleLabel = DesignSystem.label(title, font: .systemFont(ofSize: 16, weight: .semibold))
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
        case .annual: term = "year"
        case .monthly: term = "month"
        case .weekly: term = "week"
        }
        let trial = (plan.trialEligible && (plan.trialDays ?? 0) > 0)
            ? "\(plan.trialDays!) days free, then \(plan.localizedPrice)/\(term). Auto-renews. Cancel anytime."
            : nil
        return PlanVM(id: plan.id, title: planTitle(plan.period), price: plan.localizedPrice, term: term,
                      badge: plan.period == .annual ? "Save 33%" : nil, footnote: trial,
                      cta: plan.period == .annual && trial != nil ? "Start \(plan.trialDays ?? 7)-day free trial" : "Subscribe")
    }

    private static func planTitle(_ period: SubscriptionPlan.Period) -> String {
        switch period {
        case .weekly: return "Weekly"
        case .monthly: return "Billed monthly"
        case .annual: return "Billed annually"
        }
    }

    private static let fallbackPlans: [PlanVM] = [
        PlanVM(id: "com.guitaripod.payday.pro.annual", title: "Billed annually", price: "€39.99", term: "year",
               badge: "Save 33%", footnote: "7 days free, then €39.99/year. Auto-renews. Cancel anytime.",
               cta: "Start 7-day free trial"),
        PlanVM(id: "com.guitaripod.payday.pro.monthly", title: "Billed monthly", price: "€4.99", term: "month",
               badge: nil, footnote: nil, cta: "Subscribe"),
        PlanVM(id: "com.guitaripod.payday.pro.lifetime", title: "One-time purchase", price: "€89.99", term: "once",
               badge: nil, footnote: "Peppol sends metered via credit packs.", cta: "Buy Pay Day Pro"),
    ]
}

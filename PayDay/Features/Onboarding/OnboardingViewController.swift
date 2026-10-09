import UIKit

/// First-run welcome. Sells the wedge in one screen, asks for the few business
/// details a first invoice needs (or lets the user defer them), then drops the
/// user into a pre-seeded app (demo invoice + clients), so there is no empty
/// cold start.
final class OnboardingViewController: UIViewController {
    var onFinish: (() -> Void)?

    /// The whole first-run flow — welcome, then business essentials — calling
    /// `onFinish` once the user saves or defers their business.
    static func makeFlow(onFinish: @escaping (_ window: UIWindow?) -> Void) -> UIViewController {
        let welcome = OnboardingViewController()
        welcome.onFinish = { [weak welcome] in onFinish(welcome?.navigationController?.view.window) }
        let nav = UINavigationController(rootViewController: welcome)
        nav.navigationBar.prefersLargeTitles = false
        return nav
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        navigationItem.backButtonDisplayMode = .minimal
        build()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    private func showBusinessSetup() {
        guard let navigationController else { return finish(savedBusiness: false) }
        let setup = BusinessSettingsViewController(mode: .essentials)
        setup.onFinish = { [weak self] saved in self?.finish(savedBusiness: saved) }
        navigationController.pushViewController(setup, animated: true)
    }

    private func finish(savedBusiness: Bool) {
        AppLogger.shared.info("onboarding finished, business \(savedBusiness ? "saved" : "deferred")", category: .ui)
        onFinish?()
    }

    private func build() {
        let icon = UIImageView(image: UIImage(systemName: "banknote.fill"))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = DesignSystem.label(String(localized: "Pay Day", comment: "App name shown on the welcome screen"), font: DesignSystem.Typography.largeTitle())
        title.textAlignment = .center
        let subtitle = DesignSystem.label(
            String(localized: "Beautiful invoices for free — and EU-compliant e-invoices (Factur-X, Peppol) when you need them."),
            font: DesignSystem.Typography.body(), color: DesignSystem.Color.secondary)
        subtitle.textAlignment = .center

        let mandateLine = makeMandateLine()

        let features = UIStackView(arrangedSubviews: [
            feature("doc.text.fill", String(localized: "Unlimited invoices & estimates, your logo, any currency")),
            feature("checkmark.seal.fill", String(localized: "One tap to a tax-authority-ready e-invoice")),
            feature("paperplane.fill", String(localized: "Send over the Peppol network across the EU")),
            feature("sparkles", String(localized: "Draft line items from a photo or a sentence")),
        ])
        features.axis = .vertical
        features.spacing = DesignSystem.Spacing.m

        let cta = DesignSystem.primaryButton(String(localized: "Get started"))
        cta.addAction(UIAction { [weak self] _ in self?.showBusinessSetup() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle, mandateLine, features, cta].compactMap { $0 })
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.l
        stack.setCustomSpacing(DesignSystem.Spacing.xl, after: mandateLine ?? subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        let fillHeight = content.heightAnchor.constraint(equalTo: frame.heightAnchor)
        fillHeight.priority = .defaultLow
        let fillWidth = stack.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -DesignSystem.Spacing.l * 2)
        fillWidth.priority = UILayoutPriority(850)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalTo: frame.widthAnchor),
            stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: ColumnWidth.form),
            fillWidth,
            stack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: DesignSystem.Spacing.l),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -DesignSystem.Spacing.l),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            fillHeight,
        ])
    }

    /// The device region's e-invoicing deadline, when there is one worth leading
    /// with — the first thing a Belgian or French freelancer needs to hear.
    private func makeMandateLine() -> UIView? {
        let region = DashboardViewModel.countryCode(for: nil)
        guard let text = MandateCopy.welcomeLine(countryCode: region) else { return nil }
        let card = DesignSystem.card()
        card.backgroundColor = DesignSystem.Color.accentSoft
        let label = DesignSystem.label(text, font: DesignSystem.Typography.scaledSystem(15, .semibold, relativeTo: .subheadline))
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(label)
        label.pinEdges(to: card, insets: UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        return card
    }

    private func feature(_ symbol: String, _ text: String) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = DesignSystem.label(text, font: DesignSystem.Typography.body())
        let row = UIStackView(arrangedSubviews: [icon, label])
        row.axis = .horizontal
        row.spacing = DesignSystem.Spacing.m
        row.alignment = .center
        return row
    }
}

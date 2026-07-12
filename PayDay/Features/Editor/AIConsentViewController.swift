import UIKit

/// Explicit, in-app consent gate shown before Pay Day sends anything to its
/// AI drafting service. Guideline 5.1.1(i)/5.1.2(i): the user must see what
/// data is sent, who it is sent to, and grant permission before any personal
/// data leaves the device. Presented the first time an AI feature is used and
/// re-presentable from Settings for review/withdrawal.
final class AIConsentViewController: UIViewController {
    private let onDecision: (Bool) -> Void
    private let showsDecline: Bool

    /// - Parameters:
    ///   - showsDecline: `false` when reviewing an already-granted consent from
    ///     Settings (offers Withdraw instead of Not now).
    init(showsDecline: Bool = true, onDecision: @escaping (Bool) -> Void) {
        self.showsDecline = showsDecline
        self.onDecision = onDecision
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        isModalInPresentation = true
        navigationItem.title = "AI Drafting"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Close", primaryAction: UIAction { [weak self] _ in self?.finish(false) })
        buildLayout()
    }

    private func buildLayout() {
        let icon = UIImageView(image: UIImage(systemName: "sparkles",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .center

        let title = DesignSystem.label(
            "Draft with AI", font: DesignSystem.Typography.title())
        title.textAlignment = .center

        let intro = DesignSystem.label(
            "To turn your words or a photo into line items, Pay Day sends the "
            + "content you provide to a third-party AI service. You control when "
            + "this happens — nothing is sent until you tap an AI action.",
            font: DesignSystem.Typography.body(), color: DesignSystem.Color.secondary)

        let bullets = UIStackView(arrangedSubviews: [
            bullet("What is sent",
                   "Only the text you type or the photo you choose, plus the invoice "
                   + "currency. Your client list and saved invoices are not sent."),
            bullet("Who it is sent to",
                   "The request goes over an encrypted connection to Pay Day's backend "
                   + "(operated by Midgar Oy), which forwards it to OpenAI for processing."),
            bullet("How it is used",
                   "The content is used only to generate your draft. It is not stored "
                   + "by us after the response, not used to train AI models, and never "
                   + "used for advertising. You review and edit every draft."),
        ])
        bullets.axis = .vertical
        bullets.spacing = DesignSystem.Spacing.l

        let policy = UIButton(type: .system)
        policy.setTitle("Read the Privacy Policy", for: .normal)
        policy.titleLabel?.font = DesignSystem.Typography.body()
        policy.tintColor = DesignSystem.Color.accent
        policy.addAction(UIAction { [weak self] _ in self?.openPrivacyPolicy() }, for: .touchUpInside)

        let content = UIStackView(arrangedSubviews: [icon, title, intro, bullets, policy])
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = DesignSystem.Spacing.l
        content.setCustomSpacing(DesignSystem.Spacing.s, after: icon)
        content.setCustomSpacing(DesignSystem.Spacing.m, after: title)
        content.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.addSubview(content)
        view.addSubview(scroll)

        let agree = DesignSystem.primaryButton("Agree & Continue", symbol: "checkmark")
        agree.addAction(UIAction { [weak self] _ in self?.finish(true) }, for: .touchUpInside)

        let decline = DesignSystem.secondaryButton(showsDecline ? "Not Now" : "Withdraw Consent")
        decline.addAction(UIAction { [weak self] _ in self?.finish(false) }, for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [agree, decline])
        buttons.axis = .vertical
        buttons.spacing = DesignSystem.Spacing.s
        buttons.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttons)

        let m = DesignSystem.Spacing.m
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -m),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: DesignSystem.Spacing.l),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -DesignSystem.Spacing.l),
            content.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: m),
            content.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -m),

            buttons.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: m),
            buttons.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -m),
            buttons.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -m),
        ])
    }

    private func bullet(_ heading: String, _ body: String) -> UIView {
        let head = DesignSystem.label(heading, font: DesignSystem.Typography.headline())
        let detail = DesignSystem.label(body, font: DesignSystem.Typography.body(),
                                        color: DesignSystem.Color.secondary)
        let stack = UIStackView(arrangedSubviews: [head, detail])
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.xs
        return stack
    }

    private func openPrivacyPolicy() {
        guard let url = URL(string: "https://mako.midgarcorp.cc/privacy/payday") else { return }
        UIApplication.shared.open(url)
    }

    private func finish(_ granted: Bool) {
        onDecision(granted)
        dismiss(animated: true)
    }
}

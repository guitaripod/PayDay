import UIKit

/// First-run welcome. Sells the wedge in one screen, then drops the user into a
/// pre-seeded app (demo invoice + clients), so there is no empty cold start.
final class OnboardingViewController: UIViewController {
    var onFinish: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        build()
    }

    private func build() {
        let icon = UIImageView(image: UIImage(systemName: "banknote.fill"))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = DesignSystem.label("Pay Day", font: DesignSystem.Typography.largeTitle())
        title.textAlignment = .center
        let subtitle = DesignSystem.label(
            "Beautiful invoices for free — and EU-compliant e-invoices (Factur-X, Peppol) when you need them.",
            font: DesignSystem.Typography.body(), color: DesignSystem.Color.secondary)
        subtitle.textAlignment = .center

        let features = UIStackView(arrangedSubviews: [
            feature("doc.text.fill", "Unlimited invoices & estimates, your logo, any currency"),
            feature("checkmark.seal.fill", "One tap to a tax-authority-ready e-invoice"),
            feature("paperplane.fill", "Send over the Peppol network across the EU"),
            feature("sparkles", "Draft line items from a photo or a sentence"),
        ])
        features.axis = .vertical
        features.spacing = DesignSystem.Spacing.m

        let cta = DesignSystem.primaryButton("Get started")
        cta.addAction(UIAction { [weak self] _ in self?.onFinish?() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [icon, title, subtitle, features, cta])
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.l
        stack.setCustomSpacing(DesignSystem.Spacing.xl, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)

        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        let fillHeight = content.heightAnchor.constraint(equalTo: frame.heightAnchor)
        fillHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: DesignSystem.Spacing.l),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -DesignSystem.Spacing.l),
            stack.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -DesignSystem.Spacing.l * 2),
            stack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor, constant: DesignSystem.Spacing.l),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -DesignSystem.Spacing.l),
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            fillHeight,
        ])
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

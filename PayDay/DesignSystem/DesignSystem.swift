import UIKit

/// Centralised visual language for Pay Day. One source of truth for colour
/// tokens, spacing, typography, and the component factories every screen uses,
/// so the app reads as one product rather than a pile of view controllers.
enum DesignSystem {
    enum Color {
        /// Pay Day's coin-gold accent (the move scatters coins).
        static let accent = UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.98, green: 0.78, blue: 0.30, alpha: 1)
                : UIColor(red: 0.85, green: 0.62, blue: 0.10, alpha: 1)
        }
        static let accentSoft = accent.withAlphaComponent(0.16)
        static let background = UIColor.systemGroupedBackground
        static let surface = UIColor.secondarySystemGroupedBackground
        static let label = UIColor.label
        static let secondary = UIColor.secondaryLabel
        static let tertiary = UIColor.tertiaryLabel
        static let separator = UIColor.separator

        static let paid = UIColor.systemGreen
        static let overdue = UIColor.systemRed
        static let draft = UIColor.systemGray
        static let sent = UIColor.systemBlue

        static func status(_ status: String) -> UIColor {
            switch status {
            case "paid", "accepted": return paid
            case "overdue", "declined": return overdue
            case "sent", "viewed", "partiallyPaid": return sent
            default: return draft
            }
        }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 16
        static let control: CGFloat = 12
        static let pill: CGFloat = 999
    }

    enum Typography {
        static func largeTitle() -> UIFont { .systemFont(ofSize: 34, weight: .bold) }
        static func title() -> UIFont { .systemFont(ofSize: 22, weight: .bold) }
        static func headline() -> UIFont { .preferredFont(forTextStyle: .headline) }
        static func body() -> UIFont { .preferredFont(forTextStyle: .body) }
        static func mono(_ size: CGFloat = 17, weight: UIFont.Weight = .semibold) -> UIFont {
            .monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
        static func caption() -> UIFont { .preferredFont(forTextStyle: .caption1) }
    }

    @MainActor
    static func label(_ text: String? = nil, font: UIFont, color: UIColor = Color.label) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = color
        l.numberOfLines = 0
        return l
    }

    /// A prominent, coin-gold primary action button.
    @MainActor
    static func primaryButton(_ title: String, symbol: String? = nil) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.prominentGlassCompat()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Color.accent
        config.baseForegroundColor = .black
        config.attributedTitle = AttributedString(
            title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 17, weight: .semibold)]))
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 22, bottom: 14, trailing: 22)
        if let symbol { config.image = UIImage(systemName: symbol) }
        config.imagePadding = 8
        button.configuration = config
        return button
    }

    @MainActor
    static func secondaryButton(_ title: String, symbol: String? = nil) -> UIButton {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.glassCompat()
        config.cornerStyle = .capsule
        config.baseForegroundColor = Color.accent
        config.attributedTitle = AttributedString(
            title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 16, weight: .medium)]))
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18)
        if let symbol { config.image = UIImage(systemName: symbol) }
        config.imagePadding = 6
        button.configuration = config
        return button
    }

    /// A rounded surface card used for grouped content outside table views.
    @MainActor
    static func card() -> UIView {
        let view = UIView()
        view.backgroundColor = Color.surface
        view.layer.cornerRadius = Radius.card
        view.layer.cornerCurve = .continuous
        return view
    }

    /// A small status pill (Draft / Sent / Paid / Overdue …).
    @MainActor
    static func statusPill(_ statusRaw: String, title: String) -> UIView {
        let container = UIView()
        let color = Color.status(statusRaw)
        container.backgroundColor = color.withAlphaComponent(0.16)
        container.layer.cornerRadius = 8
        container.layer.cornerCurve = .continuous
        let label = UILabel()
        label.text = title.uppercased()
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
        ])
        return container
    }
}

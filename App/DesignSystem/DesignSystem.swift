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

        static func statusSymbol(_ status: String) -> String {
            switch status {
            case "paid": return "checkmark.circle.fill"
            case "accepted": return "checkmark.seal.fill"
            case "overdue": return "exclamationmark.circle.fill"
            case "declined": return "xmark.circle.fill"
            case "sent": return "paperplane.fill"
            case "viewed": return "eye.fill"
            case "partiallyPaid": return "circle.lefthalf.filled"
            case "void": return "nosign"
            default: return "pencil"
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
        /// Every face scales with the user's text-size setting (Dynamic Type).
        private static func scaled(_ style: UIFont.TextStyle, _ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
            UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight))
        }
        static func largeTitle() -> UIFont { scaled(.largeTitle, 34, .bold) }
        static func title() -> UIFont { scaled(.title1, 22, .bold) }
        static func headline() -> UIFont { .preferredFont(forTextStyle: .headline) }
        static func body() -> UIFont { .preferredFont(forTextStyle: .body) }
        static func mono(_ size: CGFloat = 17, weight: UIFont.Weight = .semibold) -> UIFont {
            UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedDigitSystemFont(ofSize: size, weight: weight))
        }
        static func caption() -> UIFont { .preferredFont(forTextStyle: .caption1) }
        static func scaledSystem(_ size: CGFloat, _ weight: UIFont.Weight, relativeTo style: UIFont.TextStyle = .body) -> UIFont {
            scaled(style, size, weight)
        }
    }

    @MainActor
    static func label(_ text: String? = nil, font: UIFont, color: UIColor = Color.label) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = font
        l.textColor = color
        l.numberOfLines = 0
        l.adjustsFontForContentSizeCategory = true
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
            title, attributes: AttributeContainer([.font: Typography.scaledSystem(17, .semibold)]))
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
            title, attributes: AttributeContainer([.font: Typography.scaledSystem(16, .medium)]))
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

    /// A small status pill with an icon (Draft / Sent / Paid / Overdue …).
    @MainActor
    static func statusPill(_ statusRaw: String, title: String) -> UIView {
        let container = UIView()
        let color = Color.status(statusRaw)
        container.backgroundColor = color.withAlphaComponent(0.16)
        container.layer.cornerRadius = 8
        container.layer.cornerCurve = .continuous

        let icon = UIImageView(image: UIImage(systemName: Color.statusSymbol(statusRaw),
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)))
        icon.tintColor = color
        let label = UILabel()
        label.text = title.uppercased()
        label.font = Typography.scaledSystem(11, .bold, relativeTo: .caption2)
        label.textColor = color
        label.adjustsFontForContentSizeCategory = true
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.spacing = 3
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isUserInteractionEnabled = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
        ])
        container.isAccessibilityElement = true
        container.accessibilityLabel = title
        return container
    }

    /// A centered empty-state placeholder (icon + title + subtitle + optional CTA),
    /// used on the dashboard, the document list, and the clients list.
    @MainActor
    static func emptyState(symbol: String, title: String, subtitle: String,
                           ctaTitle: String? = nil, ctaAction: (() -> Void)? = nil) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 52, weight: .regular)))
        icon.tintColor = Color.accent
        icon.contentMode = .center
        let titleLabel = label(title, font: Typography.title())
        titleLabel.textAlignment = .center
        let subtitleLabel = label(subtitle, font: Typography.body(), color: Color.secondary)
        subtitleLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [icon, titleLabel, subtitleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Spacing.s
        stack.setCustomSpacing(Spacing.m, after: icon)
        if let ctaTitle, let ctaAction {
            let cta = primaryButton(ctaTitle, symbol: "plus")
            cta.addAction(UIAction { _ in ctaAction() }, for: .touchUpInside)
            stack.addArrangedSubview(cta)
            stack.setCustomSpacing(Spacing.l, after: subtitleLabel)
        }
        return stack
    }
}

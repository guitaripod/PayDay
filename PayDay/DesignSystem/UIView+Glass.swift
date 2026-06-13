import UIKit

extension UIVisualEffectView {
    /// A Liquid Glass surface on iOS 26, falling back to a thin material on
    /// iOS 18. Content belongs in `contentView`; corners are continuous.
    static func paydayGlass(interactive: Bool = false, tint: UIColor? = nil, cornerRadius: CGFloat = 16) -> UIVisualEffectView {
        let view = UIVisualEffectView()
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect()
            glass.isInteractive = interactive
            if let tint { glass.tintColor = tint }
            view.effect = glass
        } else {
            view.effect = UIBlurEffect(style: .systemThinMaterial)
        }
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        return view
    }
}

extension UIButton.Configuration {
    /// Glass button on iOS 26, `.gray()` fallback on iOS 18.
    static func glassCompat() -> UIButton.Configuration {
        if #available(iOS 26.0, *) { return .glass() }
        return .gray()
    }

    /// Prominent (tinted) glass on iOS 26, `.filled()` fallback on iOS 18.
    static func prominentGlassCompat() -> UIButton.Configuration {
        if #available(iOS 26.0, *) { return .prominentGlass() }
        return .filled()
    }
}

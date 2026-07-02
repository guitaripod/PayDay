import UIKit
import PayDayKit

/// A tappable summary row for a document, reused on the dashboard and the list.
/// On the dashboard it carries its own tap, context menu, and pointer lift; in
/// the list the cell owns interaction (the row is disabled there) and reuses one
/// row per cell via `update(with:)`.
final class InvoiceRowView: UIControl {
    private let onTap: () -> Void
    private var menuDelegate: MenuDelegate?
    private let pointerDelegate = PointerDelegate()

    private let numberLabel = DesignSystem.label("", font: DesignSystem.Typography.scaledSystem(15, .semibold, relativeTo: .subheadline))
    private let clientLabel = DesignSystem.label("", font: DesignSystem.Typography.scaledSystem(13, .regular, relativeTo: .footnote), color: DesignSystem.Color.secondary)
    private let amountLabel = DesignSystem.label("", font: DesignSystem.Typography.mono(16, weight: .semibold))
    private let rightStack = UIStackView()
    private var pill: UIView?

    init(menu: (() -> UIMenu?)? = nil, onTap: @escaping () -> Void = {}) {
        self.onTap = onTap
        super.init(frame: .zero)
        backgroundColor = DesignSystem.Color.surface
        layer.cornerRadius = DesignSystem.Radius.control
        layer.cornerCurve = .continuous
        build()
        addAction(UIAction { [weak self] _ in Haptics.tap(); self?.onTap() }, for: .touchUpInside)
        if let menu {
            let delegate = MenuDelegate(provider: menu)
            menuDelegate = delegate
            addInteraction(UIContextMenuInteraction(delegate: delegate))
        }
        addInteraction(UIPointerInteraction(delegate: pointerDelegate))
    }

    convenience init(invoice: Invoice, menu: (() -> UIMenu?)? = nil, onTap: @escaping () -> Void) {
        self.init(menu: menu, onTap: onTap)
        update(with: invoice)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    func update(with invoice: Invoice) {
        let payable = Money(minorUnits: invoice.totals().summary.payableAmount.minorUnits, currency: invoice.currency)
        numberLabel.text = invoice.number
        clientLabel.text = invoice.buyer.displayName
        amountLabel.text = Format.money(payable)
        pill?.removeFromSuperview()
        let newPill = DesignSystem.statusPill(invoice.status.rawValue, title: invoice.status.displayName)
        rightStack.addArrangedSubview(newPill)
        pill = newPill
        accessibilityLabel = "\(invoice.type.displayName) \(invoice.number), \(invoice.buyer.displayName)"
        accessibilityValue = "\(Format.money(payable)), \(invoice.status.displayName)"
    }

    private func build() {
        let leftStack = UIStackView(arrangedSubviews: [numberLabel, clientLabel])
        leftStack.axis = .vertical
        leftStack.spacing = 2

        amountLabel.textAlignment = .right
        rightStack.addArrangedSubview(amountLabel)
        rightStack.axis = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [leftStack, rightStack])
        row.axis = .horizontal
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        leftStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(row)
        row.pinEdges(to: self, insets: UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14))
        isUserInteractionEnabled = true
        for sub in [numberLabel, clientLabel, amountLabel] { sub.isUserInteractionEnabled = false }

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    private final class MenuDelegate: NSObject, UIContextMenuInteractionDelegate {
        private let provider: () -> UIMenu?
        init(provider: @escaping () -> UIMenu?) { self.provider = provider }
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [provider] _ in provider() }
        }
    }

    private final class PointerDelegate: NSObject, UIPointerInteractionDelegate {
        func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
            guard let view = interaction.view else { return nil }
            return UIPointerStyle(effect: .lift(UITargetedPreview(view: view)))
        }
    }
}

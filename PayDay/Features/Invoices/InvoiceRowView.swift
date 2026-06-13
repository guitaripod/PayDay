import UIKit
import PayDayKit

/// A tappable summary row for a document, reused on the dashboard and the list.
/// On the dashboard it carries its own tap, context menu, and pointer lift; in
/// the list the cell owns interaction (the row is disabled there).
final class InvoiceRowView: UIControl {
    private let onTap: () -> Void
    private var menuDelegate: MenuDelegate?
    private let pointerDelegate = PointerDelegate()

    init(invoice: Invoice, menu: (() -> UIMenu?)? = nil, onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
        backgroundColor = DesignSystem.Color.surface
        layer.cornerRadius = DesignSystem.Radius.control
        layer.cornerCurve = .continuous
        build(invoice)
        addAction(UIAction { [weak self] _ in Haptics.tap(); self?.onTap() }, for: .touchUpInside)
        if let menu {
            let delegate = MenuDelegate(provider: menu)
            menuDelegate = delegate
            addInteraction(UIContextMenuInteraction(delegate: delegate))
        }
        addInteraction(UIPointerInteraction(delegate: pointerDelegate))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    private func build(_ invoice: Invoice) {
        let payable = Money(minorUnits: invoice.totals().summary.payableAmount.minorUnits, currency: invoice.currency)

        let number = DesignSystem.label(invoice.number, font: .systemFont(ofSize: 15, weight: .semibold))
        let client = DesignSystem.label(invoice.buyer.displayName, font: .systemFont(ofSize: 13), color: DesignSystem.Color.secondary)
        let leftStack = UIStackView(arrangedSubviews: [number, client])
        leftStack.axis = .vertical
        leftStack.spacing = 2

        let amount = DesignSystem.label(Format.money(payable), font: DesignSystem.Typography.mono(16, weight: .semibold))
        amount.textAlignment = .right
        let pill = DesignSystem.statusPill(invoice.status.rawValue, title: invoice.status.displayName)
        let rightStack = UIStackView(arrangedSubviews: [amount, pill])
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
        for sub in [number, client, amount] { sub.isUserInteractionEnabled = false }
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

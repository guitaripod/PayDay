import UIKit
import PayDayCore

/// The strings one document row shows. A list or a dashboard section formats
/// them once per document, so a cell that scrolls in only assigns text.
struct InvoiceRowModel {
    let id: Invoice.ID
    let number: String
    let client: String
    let amount: String
    let statusRaw: String
    let statusTitle: String
    let accessibilityLabel: String
    let accessibilityValue: String

    init(_ invoice: Invoice) {
        let payable = Money(minorUnits: invoice.totals().summary.payableAmount.minorUnits, currency: invoice.currency)
        let amount = Format.money(payable)
        let status = Localized.name(invoice.status)
        id = invoice.id
        number = invoice.number
        client = invoice.buyer.displayName
        self.amount = amount
        statusRaw = invoice.status.rawValue
        statusTitle = status
        accessibilityLabel = String(
            localized: "\(Localized.name(invoice.type)) \(invoice.number), \(invoice.buyer.displayName)",
            comment: "VoiceOver label for a document row: document kind, document number, client name")
        accessibilityValue = String(
            localized: "\(amount), \(status)",
            comment: "VoiceOver value for a document row: payable amount, document status")
    }
}

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
    private let pill = DesignSystem.StatusPillView()

    init(menu: (() -> UIMenu?)? = nil, onTap: @escaping () -> Void = {}) {
        self.onTap = onTap
        super.init(frame: .zero)
        backgroundColor = DesignSystem.Color.surface
        layer.cornerRadius = DesignSystem.Radius.control
        layer.cornerCurve = .continuous
        build()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (row: InvoiceRowView, _) in
            row.refreshChosenAppearance()
        }
        addAction(UIAction { [weak self] _ in Haptics.tap(); self?.onTap() }, for: .touchUpInside)
        if let menu {
            let delegate = MenuDelegate(provider: menu)
            menuDelegate = delegate
            addInteraction(UIContextMenuInteraction(delegate: delegate))
        }
        addInteraction(UIPointerInteraction(delegate: pointerDelegate))
    }

    convenience init(model: InvoiceRowModel, menu: (() -> UIMenu?)? = nil, onTap: @escaping () -> Void) {
        self.init(menu: menu, onTap: onTap)
        update(with: model)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    /// Whether the detail column is showing this document.
    var isChosen = false {
        didSet { refreshChosenAppearance() }
    }

    private func refreshChosenAppearance() {
        backgroundColor = isChosen ? DesignSystem.Color.accentSoft : DesignSystem.Color.surface
        layer.borderWidth = isChosen ? 1.5 : 0
        layer.borderColor = DesignSystem.Color.accent.resolvedColor(with: traitCollection).cgColor
    }

    func update(with model: InvoiceRowModel) {
        numberLabel.text = model.number
        clientLabel.text = model.client
        amountLabel.text = model.amount
        pill.update(statusRaw: model.statusRaw, title: model.statusTitle)
        accessibilityLabel = model.accessibilityLabel
        accessibilityValue = model.accessibilityValue
    }

    private func build() {
        let leftStack = UIStackView(arrangedSubviews: [numberLabel, clientLabel])
        leftStack.axis = .vertical
        leftStack.spacing = 2

        amountLabel.textAlignment = .right
        rightStack.addArrangedSubview(amountLabel)
        rightStack.addArrangedSubview(pill)
        rightStack.axis = .vertical
        rightStack.alignment = .trailing
        rightStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [leftStack, rightStack])
        row.axis = .horizontal
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        leftStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        leftStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for label in [numberLabel, clientLabel] { label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) }
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

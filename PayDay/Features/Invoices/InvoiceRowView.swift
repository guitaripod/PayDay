import UIKit
import PayDayKit

/// A tappable summary row for a document, reused on the dashboard and the list.
final class InvoiceRowView: UIControl {
    private let onTap: () -> Void

    init(invoice: Invoice, onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
        backgroundColor = DesignSystem.Color.surface
        layer.cornerRadius = DesignSystem.Radius.control
        layer.cornerCurve = .continuous
        build(invoice)
        addAction(UIAction { [weak self] _ in self?.onTap() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
}

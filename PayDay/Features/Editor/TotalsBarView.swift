import UIKit
import PayDayKit

/// The pinned editor footer: live total, a compliance hint, and Save.
final class TotalsBarView: UIView {
    var onSave: (() -> Void)?

    private let totalLabel = UILabel()
    private let captionLabel = UILabel()
    private let complianceLabel = UILabel()
    private let saveButton = DesignSystem.primaryButton("Save")

    private let glass = UIVisualEffectView.paydayGlass(cornerRadius: 26)

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        captionLabel.text = "Total due"
        captionLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        captionLabel.textColor = DesignSystem.Color.secondary
        totalLabel.font = DesignSystem.Typography.mono(24, weight: .bold)
        totalLabel.textColor = DesignSystem.Color.label
        complianceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        complianceLabel.numberOfLines = 1

        let left = UIStackView(arrangedSubviews: [captionLabel, totalLabel, complianceLabel])
        left.axis = .vertical
        left.spacing = 1
        left.alignment = .leading

        saveButton.addAction(UIAction { [weak self] _ in self?.onSave?() }, for: .touchUpInside)
        saveButton.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [left, saveButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DesignSystem.Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false

        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        glass.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            glass.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            glass.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
        ])
        row.pinEdges(to: glass.contentView, insets: UIEdgeInsets(top: 12, left: 18, bottom: 12, right: 14))
    }

    func update(totals: ComputedTotals) {
        totalLabel.text = Format.money(totals.summary.payableAmount)
    }

    func update(issues: [ValidationIssue]) {
        let errors = issues.filter { $0.severity == .error }
        if errors.isEmpty {
            complianceLabel.text = "✓ EN 16931 ready"
            complianceLabel.textColor = DesignSystem.Color.paid
        } else {
            complianceLabel.text = "\(errors.count) compliance issue\(errors.count == 1 ? "" : "s")"
            complianceLabel.textColor = DesignSystem.Color.overdue
        }
    }
}

import UIKit
import PayDayKit

/// The pinned editor footer: live total, a compliance hint, and Save.
final class TotalsBarView: UIView {
    var onSave: (() -> Void)?

    private let totalLabel = UILabel()
    private let captionLabel = UILabel()
    private let complianceLabel = UILabel()
    private let complianceIcon = UIImageView()
    private let saveButton = DesignSystem.primaryButton("Save")
    private var lastCompliant: Bool?

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
        captionLabel.font = DesignSystem.Typography.scaledSystem(12, .semibold, relativeTo: .caption1)
        captionLabel.textColor = DesignSystem.Color.secondary
        captionLabel.adjustsFontForContentSizeCategory = true
        totalLabel.font = DesignSystem.Typography.mono(24, weight: .bold)
        totalLabel.textColor = DesignSystem.Color.label
        totalLabel.adjustsFontForContentSizeCategory = true
        complianceLabel.font = DesignSystem.Typography.scaledSystem(11, .medium, relativeTo: .caption2)
        complianceLabel.numberOfLines = 1
        complianceLabel.adjustsFontForContentSizeCategory = true
        complianceIcon.contentMode = .scaleAspectFit
        complianceIcon.setContentHuggingPriority(.required, for: .horizontal)

        let complianceRow = UIStackView(arrangedSubviews: [complianceIcon, complianceLabel])
        complianceRow.axis = .horizontal
        complianceRow.spacing = 3
        complianceRow.alignment = .center

        let left = UIStackView(arrangedSubviews: [captionLabel, totalLabel, complianceRow])
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
        let money = Format.money(totals.summary.payableAmount)
        totalLabel.text = money
        totalLabel.accessibilityLabel = "Total due \(money)"
    }

    func update(issues: [ValidationIssue]) {
        let errors = issues.filter { $0.severity == .error }
        let compliant = errors.isEmpty
        let symbol = compliant ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
        let color = compliant ? DesignSystem.Color.paid : DesignSystem.Color.overdue
        complianceIcon.image = UIImage(systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        complianceIcon.tintColor = color
        complianceLabel.text = compliant ? "EN 16931 ready"
            : "\(errors.count) compliance issue\(errors.count == 1 ? "" : "s")"
        complianceLabel.textColor = color

        if lastCompliant != nil && lastCompliant != compliant {
            complianceIcon.addSymbolEffect(.bounce)
            compliant ? Haptics.success() : Haptics.warning()
        }
        lastCompliant = compliant
    }
}

import UIKit
import PayDayKit

/// A compact form for one line item: name, details, quantity, unit price, unit,
/// and VAT category/rate. Saves back a fully-formed `LineItem`.
final class LineItemEditorViewController: UIViewController {
    private var line: LineItem
    private let currency: Currency
    private let onSave: (LineItem) -> Void
    private let onDelete: (() -> Void)?

    private let nameField = LineItemEditorViewController.makeField(placeholder: "Description")
    private let detailField = LineItemEditorViewController.makeField(placeholder: "Details (optional)")
    private let quantityField = LineItemEditorViewController.makeField(placeholder: "Qty", keyboard: .decimalPad)
    private let priceField = LineItemEditorViewController.makeField(placeholder: "Unit price", keyboard: .decimalPad)
    private let rateField = LineItemEditorViewController.makeField(placeholder: "VAT %", keyboard: .decimalPad)
    private let categoryButton = UIButton(type: .system)
    private var selectedVATCategory: VATCategory = .standard
    private let vatCategories: [VATCategory] = [.standard, .intraCommunity, .reverseCharge, .zeroRated, .exempt]

    init(line: LineItem, currency: Currency, onSave: @escaping (LineItem) -> Void, onDelete: (() -> Void)?) {
        self.line = line
        self.currency = currency
        self.onSave = onSave
        self.onDelete = onDelete
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        title = "Line item"
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.commit() })
        build()
    }

    private func build() {
        nameField.text = line.name
        detailField.text = line.details
        quantityField.text = decimalText(line.quantity)
        priceField.text = decimalText(line.unitPrice)
        rateField.text = decimalText(line.vatRatePercent)
        selectedVATCategory = line.vatCategory
        configureCategoryButton()

        let rows: [UIView] = [
            labeled("Description", nameField),
            labeled("Details", detailField),
            labeled("Quantity", quantityField),
            labeled("Unit price (\(currency.code))", priceField),
            labeled("VAT category", categoryButton),
            labeled("VAT rate %", rateField),
        ]
        let stack = UIStackView(arrangedSubviews: rows)
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false

        if onDelete != nil {
            let delete = DesignSystem.secondaryButton("Delete line", symbol: "trash")
            delete.tintColor = DesignSystem.Color.overdue
            delete.addAction(UIAction { [weak self] _ in self?.onDelete?(); self?.dismiss(animated: true) }, for: .touchUpInside)
            stack.addArrangedSubview(delete)
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignSystem.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignSystem.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignSystem.Spacing.m),
        ])
        syncRateEnabled()
    }

    private func syncRateEnabled() {
        rateField.isEnabled = selectedCategory() == .standard
        rateField.alpha = rateField.isEnabled ? 1 : 0.4
    }

    private func commit() {
        let category = selectedCategory()
        line.name = nameField.text ?? ""
        line.details = detailField.text ?? ""
        line.quantity = Self.parseDecimal(quantityField.text) ?? 1
        line.unitPrice = Self.parseDecimal(priceField.text) ?? 0
        line.discountPercent = Self.clampPercent(line.discountPercent)
        line.vatCategory = category
        line.vatRatePercent = category == .standard ? (Self.parseDecimal(rateField.text) ?? 0) : 0
        onSave(line)
        dismiss(animated: true)
    }

    /// Constrain a per-line discount to a sane 0...100% so a >100% discount can
    /// never produce a negative line net.
    nonisolated static func clampPercent(_ value: Decimal) -> Decimal {
        min(max(value, 0), 100)
    }

    private func selectedCategory() -> VATCategory { selectedVATCategory }

    private func configureCategoryButton() {
        var config = UIButton.Configuration.gray()
        config.baseForegroundColor = DesignSystem.Color.label
        config.title = "\(selectedVATCategory.displayName) (\(selectedVATCategory.rawValue))"
        config.image = UIImage(systemName: "chevron.up.chevron.down")
        config.imagePlacement = .trailing
        config.imagePadding = 8
        config.cornerStyle = .medium
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { var c = $0; c.font = DesignSystem.Typography.body(); return c }
        categoryButton.configuration = config
        categoryButton.contentHorizontalAlignment = .leading
        categoryButton.menu = UIMenu(children: vatCategories.map { cat in
            UIAction(title: "\(cat.displayName) (\(cat.rawValue))",
                     state: cat == selectedVATCategory ? .on : .off) { [weak self] _ in
                self?.selectedVATCategory = cat
                self?.configureCategoryButton()
                self?.syncRateEnabled()
            }
        })
        categoryButton.showsMenuAsPrimaryAction = true
    }

    private func decimalText(_ value: Decimal) -> String {
        Self.decimalFormatter().string(from: value as NSDecimalNumber) ?? (value as NSDecimalNumber).stringValue
    }

    /// Parse a user-entered number honouring the current locale's decimal
    /// separator (EU users type "1,5"); falls back to a "."-separator reading so
    /// a paste or hardware keyboard with a dot still works. Pure, so testable.
    nonisolated static func parseDecimal(_ text: String?) -> Decimal? {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let number = decimalFormatter().number(from: text) { return number.decimalValue }
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = text.replacingOccurrences(of: separator, with: ".")
        return Decimal(string: normalized)
    }

    nonisolated private static func decimalFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.usesGroupingSeparator = false
        formatter.generatesDecimalNumbers = true
        formatter.maximumFractionDigits = 6
        return formatter
    }

    private func labeled(_ caption: String, _ control: UIView) -> UIView {
        let label = DesignSystem.label(caption, font: DesignSystem.Typography.scaledSystem(12, .semibold, relativeTo: .caption2), color: DesignSystem.Color.secondary)
        let stack = UIStackView(arrangedSubviews: [label, control])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    private static func makeField(placeholder: String, keyboard: UIKeyboardType = .default) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.keyboardType = keyboard
        field.font = DesignSystem.Typography.body()
        return field
    }
}

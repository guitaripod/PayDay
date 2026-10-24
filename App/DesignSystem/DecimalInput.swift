import Foundation

/// Locale-aware decimal parsing and formatting for user-facing number fields,
/// shared by every screen that reads or shows a plain decimal (VAT rates,
/// quantities, unit prices). EU users type "1,5"; a pasted "1.5" still parses.
nonisolated enum DecimalInput {
    static func parse(_ text: String?) -> Decimal? {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if let number = formatter().number(from: text) { return number.decimalValue }
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = text.replacingOccurrences(of: separator, with: ".")
        return Decimal(string: normalized)
    }

    static func text(_ value: Decimal) -> String {
        formatter().string(from: value as NSDecimalNumber) ?? (value as NSDecimalNumber).stringValue
    }

    private static func formatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.usesGroupingSeparator = false
        formatter.generatesDecimalNumbers = true
        formatter.maximumFractionDigits = 6
        return formatter
    }
}

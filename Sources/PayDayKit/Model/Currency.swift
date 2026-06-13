import Foundation

/// An ISO 4217 currency with its minor-unit precision. Monetary amounts are
/// stored as integer minor units (cents), so the digit count is the contract
/// between a `Money` value and the decimal string emitted into invoices.
public struct Currency: Sendable, Equatable, Hashable, Codable {
    public let code: String
    public let minorUnitDigits: Int

    public init(code: String, minorUnitDigits: Int) {
        self.code = code.uppercased()
        self.minorUnitDigits = minorUnitDigits
    }

    /// Resolve a known currency by ISO 4217 code, defaulting to 2 minor-unit
    /// digits for anything not in the table (the overwhelming common case).
    public init(_ code: String) {
        let upper = code.uppercased()
        self = Currency.known[upper] ?? Currency(code: upper, minorUnitDigits: 2)
    }

    public static let eur = Currency(code: "EUR", minorUnitDigits: 2)
    public static let usd = Currency(code: "USD", minorUnitDigits: 2)
    public static let gbp = Currency(code: "GBP", minorUnitDigits: 2)

    /// Subset of ISO 4217 covering currencies with non-default minor units plus
    /// the majors a freelancer invoice app actually issues in.
    static let known: [String: Currency] = [
        "EUR": eur, "USD": usd, "GBP": gbp,
        "CHF": Currency(code: "CHF", minorUnitDigits: 2),
        "SEK": Currency(code: "SEK", minorUnitDigits: 2),
        "NOK": Currency(code: "NOK", minorUnitDigits: 2),
        "DKK": Currency(code: "DKK", minorUnitDigits: 2),
        "PLN": Currency(code: "PLN", minorUnitDigits: 2),
        "CZK": Currency(code: "CZK", minorUnitDigits: 2),
        "CAD": Currency(code: "CAD", minorUnitDigits: 2),
        "AUD": Currency(code: "AUD", minorUnitDigits: 2),
        "JPY": Currency(code: "JPY", minorUnitDigits: 0),
        "ISK": Currency(code: "ISK", minorUnitDigits: 0),
        "HUF": Currency(code: "HUF", minorUnitDigits: 2),
        "BHD": Currency(code: "BHD", minorUnitDigits: 3),
        "KWD": Currency(code: "KWD", minorUnitDigits: 3),
    ]

    /// 10^digits, the scale used to convert between minor units and a decimal.
    var scale: Decimal {
        var result: Decimal = 1
        for _ in 0..<minorUnitDigits { result *= 10 }
        return result
    }
}

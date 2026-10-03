import Foundation

/// The invoicing defaults a new seller in a country starts from: the currency
/// they bill in, the standard VAT rate their lines carry, and the e-invoice
/// profile Pay Day emits. A starting point only — the seller can change every
/// one of them in their business settings.
public struct RegionalDefaults: Sendable, Equatable {
    public let countryCode: String
    public let currencyCode: String
    public let standardVATRatePercent: Decimal
    public let eInvoiceProfile: EInvoiceProfile

    /// The defaults for `countryCode`, or nil for a country Pay Day does not
    /// set a seller up in.
    public static func forCountry(_ countryCode: String) -> RegionalDefaults? {
        let code = countryCode.trimmed.uppercased()
        guard let (currency, rate) = table[code] else { return nil }
        return RegionalDefaults(countryCode: code, currencyCode: currency,
                                standardVATRatePercent: Decimal(string: rate) ?? 0, eInvoiceProfile: .en16931)
    }

    /// Every country a seller can pick when setting up: the EU member states
    /// plus the European neighbours that invoice into it.
    public static var supportedCountryCodes: [String] { table.keys.sorted() }

    private static let table: [String: (currency: String, rate: String)] = [
        "AT": ("EUR", "20"), "BE": ("EUR", "21"), "BG": ("EUR", "20"), "HR": ("EUR", "25"),
        "CY": ("EUR", "19"), "CZ": ("CZK", "21"), "DK": ("DKK", "25"), "EE": ("EUR", "24"),
        "FI": ("EUR", "25.5"), "FR": ("EUR", "20"), "DE": ("EUR", "19"), "GR": ("EUR", "24"),
        "HU": ("HUF", "27"), "IE": ("EUR", "23"), "IT": ("EUR", "22"), "LV": ("EUR", "21"),
        "LT": ("EUR", "21"), "LU": ("EUR", "17"), "MT": ("EUR", "18"), "NL": ("EUR", "21"),
        "PL": ("PLN", "23"), "PT": ("EUR", "23"), "RO": ("RON", "21"), "SK": ("EUR", "23"),
        "SI": ("EUR", "22"), "ES": ("EUR", "21"), "SE": ("SEK", "25"),
        "NO": ("NOK", "25"), "CH": ("CHF", "8.1"), "GB": ("GBP", "20"),
    ]
}

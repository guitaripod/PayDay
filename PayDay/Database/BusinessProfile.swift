import Foundation
import PayDayKit

/// The user's own business: the seller party plus app-level defaults and
/// branding that are not part of the EN 16931 model. Persisted as a single row.
struct BusinessProfile: Codable, Sendable, Equatable {
    var seller: Party
    var defaultCurrencyCode: String
    var defaultVATRatePercent: Double
    var defaultPaymentTermDays: Int
    var defaultEInvoiceProfile: EInvoiceProfile
    var paymentMeans: PaymentMeans
    var defaultPaymentTerms: String
    var logoFileName: String?
    var accentHex: String?

    init(
        seller: Party = Party(id: "business", legalName: ""),
        defaultCurrencyCode: String = "EUR",
        defaultVATRatePercent: Double = 24,
        defaultPaymentTermDays: Int = 14,
        defaultEInvoiceProfile: EInvoiceProfile = .en16931,
        paymentMeans: PaymentMeans = PaymentMeans(),
        defaultPaymentTerms: String = "",
        logoFileName: String? = nil,
        accentHex: String? = nil
    ) {
        self.seller = seller
        self.defaultCurrencyCode = defaultCurrencyCode
        self.defaultVATRatePercent = defaultVATRatePercent
        self.defaultPaymentTermDays = defaultPaymentTermDays
        self.defaultEInvoiceProfile = defaultEInvoiceProfile
        self.paymentMeans = paymentMeans
        self.defaultPaymentTerms = defaultPaymentTerms
        self.logoFileName = logoFileName
        self.accentHex = accentHex
    }

    var currency: Currency { Currency(defaultCurrencyCode) }
    var isConfigured: Bool { !seller.legalName.trimmed.isEmpty }

    /// Tolerant decoder: a future field addition must never make an existing
    /// stored profile undecodable (which would silently wipe the seller's
    /// identity, IBAN, and branding). Every field falls back to its default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BusinessProfile()
        seller = try c.decodeIfPresent(Party.self, forKey: .seller) ?? d.seller
        defaultCurrencyCode = try c.decodeIfPresent(String.self, forKey: .defaultCurrencyCode) ?? d.defaultCurrencyCode
        defaultVATRatePercent = try c.decodeIfPresent(Double.self, forKey: .defaultVATRatePercent) ?? d.defaultVATRatePercent
        defaultPaymentTermDays = try c.decodeIfPresent(Int.self, forKey: .defaultPaymentTermDays) ?? d.defaultPaymentTermDays
        defaultEInvoiceProfile = try c.decodeIfPresent(EInvoiceProfile.self, forKey: .defaultEInvoiceProfile) ?? d.defaultEInvoiceProfile
        paymentMeans = try c.decodeIfPresent(PaymentMeans.self, forKey: .paymentMeans) ?? d.paymentMeans
        defaultPaymentTerms = try c.decodeIfPresent(String.self, forKey: .defaultPaymentTerms) ?? d.defaultPaymentTerms
        logoFileName = try c.decodeIfPresent(String.self, forKey: .logoFileName)
        accentHex = try c.decodeIfPresent(String.self, forKey: .accentHex)
    }
}

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
}

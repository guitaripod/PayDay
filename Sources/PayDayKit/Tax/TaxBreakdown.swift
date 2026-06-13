import Foundation

/// One VAT breakdown group (BG-23): all lines sharing a (category, rate) pair,
/// with the taxable base (BT-116), the VAT amount (BT-117), and, when the
/// category requires it, the exemption reason (BT-120).
public struct TaxBreakdown: Sendable, Equatable, Hashable, Codable {
    public let category: VATCategory
    public let ratePercent: Decimal
    public let taxableBase: Money
    public let taxAmount: Money
    public let exemptionReason: String

    public init(
        category: VATCategory,
        ratePercent: Decimal,
        taxableBase: Money,
        taxAmount: Money,
        exemptionReason: String
    ) {
        self.category = category
        self.ratePercent = ratePercent
        self.taxableBase = taxableBase
        self.taxAmount = taxAmount
        self.exemptionReason = exemptionReason
    }
}

/// The document monetary summation (BG-22).
public struct MonetarySummary: Sendable, Equatable, Hashable, Codable {
    /// BT-106 — sum of line net amounts.
    public let lineTotal: Money
    /// BT-107 / BT-108 — document-level allowances and charges.
    public let allowanceTotal: Money
    public let chargeTotal: Money
    /// BT-109 — total without VAT.
    public let taxExclusiveTotal: Money
    /// BT-110 — total VAT.
    public let taxTotal: Money
    /// BT-112 — total with VAT.
    public let taxInclusiveTotal: Money
    /// BT-113 — amount already paid.
    public let prepaidAmount: Money
    /// BT-115 — amount due for payment.
    public let payableAmount: Money

    public init(
        lineTotal: Money,
        allowanceTotal: Money,
        chargeTotal: Money,
        taxExclusiveTotal: Money,
        taxTotal: Money,
        taxInclusiveTotal: Money,
        prepaidAmount: Money,
        payableAmount: Money
    ) {
        self.lineTotal = lineTotal
        self.allowanceTotal = allowanceTotal
        self.chargeTotal = chargeTotal
        self.taxExclusiveTotal = taxExclusiveTotal
        self.taxTotal = taxTotal
        self.taxInclusiveTotal = taxInclusiveTotal
        self.prepaidAmount = prepaidAmount
        self.payableAmount = payableAmount
    }
}

/// The fully-computed financial picture of an invoice: per-line nets, the VAT
/// breakdown groups, and the monetary summation — everything the renderers and
/// XML writers consume.
public struct ComputedTotals: Sendable, Equatable, Hashable, Codable {
    public let currency: Currency
    public let lineNets: [Money]
    public let breakdowns: [TaxBreakdown]
    public let summary: MonetarySummary

    public init(currency: Currency, lineNets: [Money], breakdowns: [TaxBreakdown], summary: MonetarySummary) {
        self.currency = currency
        self.lineNets = lineNets
        self.breakdowns = breakdowns
        self.summary = summary
    }
}

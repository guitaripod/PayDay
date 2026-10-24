import Foundation

/// A document-level allowance (discount) or charge (surcharge) applied to the
/// whole invoice (BG-20 / BG-21).
public struct DocumentAdjustment: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String
    public var isCharge: Bool
    public var reason: String
    public var amount: Decimal
    public var vatCategory: VATCategory
    public var vatRatePercent: Decimal

    public init(
        id: String,
        isCharge: Bool,
        reason: String,
        amount: Decimal,
        vatCategory: VATCategory = .standard,
        vatRatePercent: Decimal = 0
    ) {
        self.id = id
        self.isCharge = isCharge
        self.reason = reason
        self.amount = amount
        self.vatCategory = vatCategory
        self.vatRatePercent = vatRatePercent
    }

    /// The VAT rate the tax engine applies to this adjustment — the declared
    /// rate for standard-rated adjustments, 0 for every other category.
    public var effectiveRate: Decimal {
        vatCategory.allowsPositiveRate ? vatRatePercent : 0
    }
}

/// The invoice/estimate/credit-note aggregate — the single source of truth from
/// which both the human PDF and the EN 16931 XML are produced, so they can
/// never disagree. Money totals are derived on demand via ``TaxEngine``.
public struct Invoice: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String
    public var type: DocumentType
    public var status: DocumentStatus
    public var number: String
    public var issueDate: CalendarDate
    public var dueDate: CalendarDate
    public var currency: Currency

    public var seller: Party
    public var buyer: Party

    public var lines: [LineItem]
    public var adjustments: [DocumentAdjustment]
    public var paymentMeans: PaymentMeans

    /// BT-20 — free-text payment terms shown to the buyer.
    public var paymentTerms: String
    /// BT-22 — a general note on the document.
    public var note: String
    /// Buyer's purchase-order reference (BT-13), when supplied.
    public var purchaseOrderReference: String
    /// Buyer reference (BT-10) — a routing/cost-centre code the buyer requires
    /// (mandatory under XRechnung; "Leitweg-ID" in Germany). Optional otherwise.
    public var buyerReference: String
    /// BT-113 — any amount already prepaid, in minor units of `currency`.
    public var prepaidMinorUnits: Int

    /// For a credit note, the invoice it corrects (BT-25).
    public var precedingInvoiceNumber: String

    public init(
        id: String,
        type: DocumentType,
        status: DocumentStatus = .draft,
        number: String,
        issueDate: CalendarDate,
        dueDate: CalendarDate,
        currency: Currency = .eur,
        seller: Party,
        buyer: Party,
        lines: [LineItem] = [],
        adjustments: [DocumentAdjustment] = [],
        paymentMeans: PaymentMeans = PaymentMeans(),
        paymentTerms: String = "",
        note: String = "",
        purchaseOrderReference: String = "",
        buyerReference: String = "",
        prepaidMinorUnits: Int = 0,
        precedingInvoiceNumber: String = ""
    ) {
        self.id = id
        self.type = type
        self.status = status
        self.number = number
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.currency = currency
        self.seller = seller
        self.buyer = buyer
        self.lines = lines
        self.adjustments = adjustments
        self.paymentMeans = paymentMeans
        self.paymentTerms = paymentTerms
        self.note = note
        self.purchaseOrderReference = purchaseOrderReference
        self.buyerReference = buyerReference
        self.prepaidMinorUnits = prepaidMinorUnits
        self.precedingInvoiceNumber = precedingInvoiceNumber
    }

    /// Tolerant decoding: persisted invoices are stored as a JSON payload, so a
    /// later app version that adds a field must still decode an older row.
    /// Swift's synthesized `Decodable` throws on a missing non-optional key — so
    /// every field is decoded with `decodeIfPresent` and a default, making the
    /// stored aggregate forward- and backward-compatible across releases.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        type = try c.decodeIfPresent(DocumentType.self, forKey: .type) ?? .invoice
        status = try c.decodeIfPresent(DocumentStatus.self, forKey: .status) ?? .draft
        number = try c.decodeIfPresent(String.self, forKey: .number) ?? ""
        issueDate = try c.decodeIfPresent(CalendarDate.self, forKey: .issueDate) ?? CalendarDate(year: 2000, month: 1, day: 1)
        dueDate = try c.decodeIfPresent(CalendarDate.self, forKey: .dueDate) ?? issueDate
        currency = try c.decodeIfPresent(Currency.self, forKey: .currency) ?? .eur
        seller = try c.decodeIfPresent(Party.self, forKey: .seller) ?? Party(id: "seller", legalName: "")
        buyer = try c.decodeIfPresent(Party.self, forKey: .buyer) ?? Party(id: "buyer", legalName: "")
        lines = try c.decodeIfPresent([LineItem].self, forKey: .lines) ?? []
        adjustments = try c.decodeIfPresent([DocumentAdjustment].self, forKey: .adjustments) ?? []
        paymentMeans = try c.decodeIfPresent(PaymentMeans.self, forKey: .paymentMeans) ?? PaymentMeans()
        paymentTerms = try c.decodeIfPresent(String.self, forKey: .paymentTerms) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        purchaseOrderReference = try c.decodeIfPresent(String.self, forKey: .purchaseOrderReference) ?? ""
        buyerReference = try c.decodeIfPresent(String.self, forKey: .buyerReference) ?? ""
        prepaidMinorUnits = try c.decodeIfPresent(Int.self, forKey: .prepaidMinorUnits) ?? 0
        precedingInvoiceNumber = try c.decodeIfPresent(String.self, forKey: .precedingInvoiceNumber) ?? ""
    }

    /// Compute all derived monetary values for this invoice.
    public func totals() -> ComputedTotals {
        TaxEngine.compute(self)
    }

    public var prepaidMoney: Money {
        Money(minorUnits: prepaidMinorUnits, currency: currency)
    }
}

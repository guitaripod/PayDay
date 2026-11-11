import Foundation
import PayDayCore

/// Localized presentation names for `PayDayCore`'s domain enums. The Kit stays
/// English-only so it keeps compiling and testing on Linux; every one of its
/// names that a person reads is resolved here, at the app seam. Keys are
/// symbolic because the plain English words collide with unrelated keys that
/// already carry a different sense (the "Invoice" swipe action is a verb, the
/// "Draft" AI action is a verb, the "Overdue" dashboard tile is a plural).
enum Localized {
    static func name(_ type: DocumentType) -> String {
        switch type {
        case .invoice: return String(localized: "documentType.invoice", comment: "Document kind: a sales invoice")
        case .estimate: return String(localized: "documentType.estimate", comment: "Document kind: a quote / estimate")
        case .creditNote: return String(localized: "documentType.creditNote", comment: "Document kind: an EN 16931 credit note")
        }
    }

    static func name(_ status: DocumentStatus) -> String {
        switch status {
        case .draft: return String(localized: "documentStatus.draft", comment: "Document status pill: not issued yet")
        case .sent: return String(localized: "documentStatus.sent", comment: "Document status pill: delivered to the client")
        case .viewed: return String(localized: "documentStatus.viewed", comment: "Document status pill: opened by the client")
        case .partiallyPaid: return String(localized: "documentStatus.partiallyPaid", comment: "Document status pill: part of the amount is settled")
        case .paid: return String(localized: "documentStatus.paid", comment: "Document status pill: settled in full")
        case .overdue: return String(localized: "documentStatus.overdue", comment: "Document status pill: past the due date")
        case .void: return String(localized: "documentStatus.void", comment: "Document status pill: cancelled, no longer payable")
        case .accepted: return String(localized: "documentStatus.accepted", comment: "Estimate status pill: the client accepted the quote")
        case .declined: return String(localized: "documentStatus.declined", comment: "Estimate status pill: the client rejected the quote")
        }
    }

    static func name(_ category: VATCategory) -> String {
        switch category {
        case .standard: return String(localized: "vatCategory.standard", comment: "EN 16931 VAT category S: the standard national rate")
        case .zeroRated: return String(localized: "vatCategory.zeroRated", comment: "EN 16931 VAT category Z: zero rated goods")
        case .exempt: return String(localized: "vatCategory.exempt", comment: "EN 16931 VAT category E: exempt from VAT")
        case .reverseCharge: return String(localized: "vatCategory.reverseCharge", comment: "EN 16931 VAT category AE: the buyer accounts for the VAT")
        case .intraCommunity: return String(localized: "vatCategory.intraCommunity", comment: "EN 16931 VAT category K: intra-Community supply")
        case .export: return String(localized: "vatCategory.export", comment: "EN 16931 VAT category G: export outside the EU")
        case .outsideScope: return String(localized: "vatCategory.outsideScope", comment: "EN 16931 VAT category O: outside the scope of VAT")
        }
    }

    /// A validation issue's message in the interface language. Rules whose wording carries amounts (the summation
    /// and VAT breakdown checks) keep the Kit's English message.
    static func message(_ issue: ValidationIssue) -> String {
        switch issue.rule {
        case "BR-02": return String(localized: "validation.BR-02", defaultValue: "An invoice must have an invoice number (BT-1).", comment: "EN 16931 / Peppol validation message for rule BR-02; keep the BT/BG numbers")
        case "BR-06": return String(localized: "validation.BR-06", defaultValue: "An invoice must have the seller name (BT-27).", comment: "EN 16931 / Peppol validation message for rule BR-06; keep the BT/BG numbers")
        case "BR-CO-26": return String(localized: "validation.BR-CO-26", defaultValue: "The seller must be identifiable by a VAT identifier (BT-31) or a legal registration (BT-30).", comment: "EN 16931 / Peppol validation message for rule BR-CO-26; keep the BT/BG numbers")
        case "BR-07": return String(localized: "validation.BR-07", defaultValue: "An invoice must have the buyer name (BT-44).", comment: "EN 16931 / Peppol validation message for rule BR-07; keep the BT/BG numbers")
        case "BR-09": return String(localized: "validation.BR-09", defaultValue: "The seller address must contain a country code (BT-40).", comment: "EN 16931 / Peppol validation message for rule BR-09; keep the BT/BG numbers")
        case "BR-11": return String(localized: "validation.BR-11", defaultValue: "The buyer address must contain a country code (BT-55).", comment: "EN 16931 / Peppol validation message for rule BR-11; keep the BT/BG numbers")
        case "BR-16": return String(localized: "validation.BR-16", defaultValue: "An invoice must have at least one invoice line (BG-25).", comment: "EN 16931 / Peppol validation message for rule BR-16; keep the BT/BG numbers")
        case "BR-05": return String(localized: "validation.BR-05", defaultValue: "The invoice must have a valid 3-letter currency code (BT-5).", comment: "EN 16931 / Peppol validation message for rule BR-05; keep the BT/BG numbers")
        case "BR-CO-25": return String(localized: "validation.BR-CO-25", defaultValue: "The payment due date (BT-9) is before the issue date (BT-2).", comment: "EN 16931 / Peppol validation message for rule BR-CO-25; keep the BT/BG numbers")
        case "PEPPOL-EN16931-R003": return String(localized: "validation.PEPPOL-EN16931-R003", defaultValue: "A buyer reference (BT-10) or a purchase order reference (BT-13) is required for delivery over the Peppol network.", comment: "EN 16931 / Peppol validation message for rule PEPPOL-EN16931-R003; keep the BT/BG numbers")
        case "PEPPOL-EN16931-R020": return String(localized: "validation.PEPPOL-EN16931-R020", defaultValue: "Delivery over the Peppol network requires the seller electronic address (BT-34).", comment: "EN 16931 / Peppol validation message for rule PEPPOL-EN16931-R020; keep the BT/BG numbers")
        case "PEPPOL-EN16931-R010": return String(localized: "validation.PEPPOL-EN16931-R010", defaultValue: "Delivery over the Peppol network requires the buyer electronic address (BT-49).", comment: "EN 16931 / Peppol validation message for rule PEPPOL-EN16931-R010; keep the BT/BG numbers")
        default: return issue.message
        }
    }

    /// A unit of measure as a person reads it on an invoice line; the UN/ECE code stays on the wire.
    static func name(_ unit: UnitCode) -> String {
        switch unit {
        case .piece: return String(localized: "unit.piece", defaultValue: "piece", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 piece")
        case .hour: return String(localized: "unit.hour", defaultValue: "hour", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 hour")
        case .day: return String(localized: "unit.day", defaultValue: "day", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 day")
        case .month: return String(localized: "unit.month", defaultValue: "month", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 month")
        case .kilogram: return String(localized: "unit.kilogram", defaultValue: "kg", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 kg")
        case .litre: return String(localized: "unit.litre", defaultValue: "litre", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 litre")
        case .metre: return String(localized: "unit.metre", defaultValue: "metre", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 metre")
        case .squareMetre: return String(localized: "unit.squareMetre", defaultValue: "m²", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 m²")
        case .kilometre: return String(localized: "unit.kilometre", defaultValue: "km", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 km")
        case .lumpSum: return String(localized: "unit.lumpSum", defaultValue: "lump sum", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 lump sum")
        case .word: return String(localized: "unit.word", defaultValue: "word", comment: "Unit of measure after a quantity on an invoice line, e.g. 3 word")
        }
    }
}

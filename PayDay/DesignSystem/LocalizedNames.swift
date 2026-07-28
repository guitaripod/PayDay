import Foundation
import PayDayKit

/// Localized presentation names for `PayDayKit`'s domain enums. The Kit stays
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
}

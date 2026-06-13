import Foundation

/// What a document is. Estimates (quotes) share the invoice model but are never
/// e-invoiced; invoices and credit notes carry UNCL 1001 type codes (BT-3) and
/// are eligible for Factur-X / Peppol output.
public enum DocumentType: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case invoice
    case estimate
    case creditNote

    /// UNCL 1001 document type code for the e-invoice payload.
    public var typeCode: String {
        switch self {
        case .invoice: return "380"
        case .creditNote: return "381"
        case .estimate: return "380"
        }
    }

    public var isEInvoiceable: Bool {
        self != .estimate
    }

    public var displayName: String {
        switch self {
        case .invoice: return "Invoice"
        case .estimate: return "Estimate"
        case .creditNote: return "Credit Note"
        }
    }

    public var noun: String {
        switch self {
        case .invoice: return "invoice"
        case .estimate: return "estimate"
        case .creditNote: return "credit note"
        }
    }
}

/// Lifecycle status of a document. Drives the dashboard, overdue automation,
/// and what actions are offered.
public enum DocumentStatus: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case draft
    case sent
    case viewed
    case partiallyPaid
    case paid
    case overdue
    case void
    case accepted
    case declined

    public var displayName: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .viewed: return "Viewed"
        case .partiallyPaid: return "Partially Paid"
        case .paid: return "Paid"
        case .overdue: return "Overdue"
        case .void: return "Void"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        }
    }

    public var isSettled: Bool {
        self == .paid || self == .void
    }
}

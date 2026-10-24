import Foundation

/// EN 16931 VAT category codes (UNCL 5305 subset, BT-118 / BT-151). Each case
/// carries the rules a validator and the tax engine enforce: whether a positive
/// rate is allowed, and whether an exemption reason (BT-120) is required.
public enum VATCategory: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// Standard rate — a positive percentage applies.
    case standard = "S"
    /// Zero rated goods.
    case zeroRated = "Z"
    /// Exempt from VAT.
    case exempt = "E"
    /// VAT reverse charge — buyer accounts for VAT (domestic B2B reverse charge).
    case reverseCharge = "AE"
    /// Intra-community supply of goods/services (0%, buyer self-accounts).
    case intraCommunity = "K"
    /// Free export item, VAT not charged.
    case export = "G"
    /// Services outside the scope of VAT.
    case outsideScope = "O"

    public var allowsPositiveRate: Bool {
        self == .standard
    }

    /// BR-O-5 / BR-O-10: an outside-scope (O) line or breakdown must not carry a
    /// VAT rate at all — every other category emits one (0 or positive).
    public var emitsRate: Bool {
        self != .outsideScope
    }

    public var requiresZeroRate: Bool {
        switch self {
        case .reverseCharge, .intraCommunity, .export, .outsideScope, .zeroRated, .exempt:
            return true
        case .standard:
            return false
        }
    }

    /// EN 16931 requires an exemption reason (BT-120) for these categories.
    public var requiresExemptionReason: Bool {
        switch self {
        case .exempt, .reverseCharge, .intraCommunity, .export, .outsideScope:
            return true
        case .standard, .zeroRated:
            return false
        }
    }

    /// Whether both seller and buyer VAT identifiers are mandatory.
    public var requiresBothVATIDs: Bool {
        self == .reverseCharge || self == .intraCommunity
    }

    /// A sensible default exemption-reason text for the category, used when the
    /// user has not supplied one.
    public var defaultExemptionReason: String {
        switch self {
        case .reverseCharge: return "Reverse charge"
        case .intraCommunity: return "Intra-Community supply"
        case .export: return "Export outside the EU, exempt"
        case .outsideScope: return "Outside the scope of VAT"
        case .exempt: return "Exempt"
        case .zeroRated: return "Zero rated"
        case .standard: return ""
        }
    }

    public var displayName: String {
        switch self {
        case .standard: return "Standard rate"
        case .zeroRated: return "Zero rated"
        case .exempt: return "Exempt"
        case .reverseCharge: return "Reverse charge"
        case .intraCommunity: return "Intra-Community"
        case .export: return "Export"
        case .outsideScope: return "Outside scope"
        }
    }
}

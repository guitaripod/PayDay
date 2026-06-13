import Foundation

/// The Factur-X / EN 16931 conformance profile to emit. Pay Day issues the
/// `en16931` (COMFORT) profile by default — full semantic compliance — and can
/// drop to `basic` for the leanest compliant payload.
public enum EInvoiceProfile: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case basic
    case en16931

    /// The CII `GuidelineSpecifiedDocumentContextParameter/ID` URN (BT-24).
    public var ciiGuidelineID: String {
        switch self {
        case .basic: return "urn:cen.eu:en16931:2017#compliant#urn:factur-x.eu:1p0:basic"
        case .en16931: return "urn:cen.eu:en16931:2017"
        }
    }

    /// The Factur-X XMP `ConformanceLevel` written into the PDF/A-3 metadata.
    public var xmpConformanceLevel: String {
        switch self {
        case .basic: return "BASIC"
        case .en16931: return "EN 16931"
        }
    }

    public var displayName: String {
        switch self {
        case .basic: return "Factur-X Basic"
        case .en16931: return "EN 16931 (Comfort)"
        }
    }
}

/// Peppol BIS Billing 3.0 customization/profile identifiers (UBL BT-24 / BT-23).
public enum PeppolIdentifiers {
    public static let customizationID =
        "urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0"
    public static let profileID = "urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"
}

public enum EInvoiceError: Error, Sendable, Equatable {
    case notEInvoiceable(DocumentType)
    case missingSeller
    case missingBuyer
    case noLines
    case validationFailed([ValidationIssue])
}

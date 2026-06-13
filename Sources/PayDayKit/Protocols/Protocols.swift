import Foundation

/// Validates an EU VAT identifier against the authority (VIES), brokered by the
/// Worker. The app implementation performs the authenticated HTTPS round-trip.
/// Validation is always advisory — a freelancer offline must still issue.
public protocol VATValidating: Sendable {
    func validate(vatID: String) async throws -> VATValidationResult
}

/// The result of a VIES lookup. `reachable == false` means the service could
/// not be consulted (network/authority down), which must never block issuing.
public struct VATValidationResult: Sendable, Equatable, Hashable, Codable {
    public let vatID: String
    public let valid: Bool
    public let reachable: Bool
    public let name: String?
    public let address: String?

    public init(vatID: String, valid: Bool, reachable: Bool, name: String? = nil, address: String? = nil) {
        self.vatID = vatID
        self.valid = valid
        self.reachable = reachable
        self.name = name
        self.address = address
    }

    public static func unreachable(_ vatID: String) -> VATValidationResult {
        VATValidationResult(vatID: vatID, valid: false, reachable: false)
    }
}

/// Transmits a compliant e-invoice over the Peppol network through a brokered
/// access-point gateway. The app/worker own AS4; the Kit only describes the
/// contract and the state stream.
public protocol PeppolTransmitting: Sendable {
    /// Look up whether a participant is reachable on Peppol (SML/SMP).
    func lookup(endpointID: String, schemeID: String) async throws -> PeppolReachability
    /// Send a UBL document; emits progress until delivered or failed.
    func send(ublXML: String, recipient: PeppolRecipient) -> AsyncThrowingStream<PeppolSendEvent, Error>
}

public struct PeppolRecipient: Sendable, Equatable, Hashable, Codable {
    public let endpointID: String
    public let schemeID: String
    public let countryCode: String

    public init(endpointID: String, schemeID: String, countryCode: String) {
        self.endpointID = endpointID
        self.schemeID = schemeID
        self.countryCode = countryCode
    }
}

public struct PeppolReachability: Sendable, Equatable, Hashable, Codable {
    public let reachable: Bool
    public let supportedDocumentTypes: [String]

    public init(reachable: Bool, supportedDocumentTypes: [String] = []) {
        self.reachable = reachable
        self.supportedDocumentTypes = supportedDocumentTypes
    }
}

public enum PeppolSendEvent: Sendable, Equatable, Hashable {
    case validating
    case submitting
    case accepted(transmissionID: String)
    case delivered(transmissionID: String)
    case failed(reason: String)
}

/// Foreign-exchange reference rates (ECB), brokered by the Worker, for
/// presenting an invoice total in a second currency. Never used to alter the
/// invoice's own monetary terms — display only.
public protocol ExchangeRateProviding: Sendable {
    func rate(from base: String, to quote: String) async throws -> Decimal
}

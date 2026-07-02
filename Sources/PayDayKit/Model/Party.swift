import Foundation

/// A trade party — the seller (BG-4) or buyer (BG-7). The same value type
/// represents the user's own business and each client; which role it plays is
/// decided by where it sits on an ``Invoice``.
public struct Party: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String
    public var legalName: String
    public var tradingName: String
    public var contactName: String
    public var email: String
    public var phone: String
    public var address: PostalAddress

    /// EN 16931 BT-31 / BT-48 — the VAT identifier, including the country
    /// prefix (e.g. "FI12345678"). Empty when the party is not VAT registered.
    public var vatID: String

    /// BT-30 / BT-47 — legal registration identifier (company number).
    public var legalRegistrationID: String

    /// Peppol participant identifier with its scheme, e.g.
    /// "0208:0123456789" (Belgian enterprise) or "9930:DE..." . Empty until the
    /// party is reachable on the Peppol network.
    public var peppolEndpointID: String
    public var peppolSchemeID: String

    public init(
        id: String,
        legalName: String,
        tradingName: String = "",
        contactName: String = "",
        email: String = "",
        phone: String = "",
        address: PostalAddress = PostalAddress(),
        vatID: String = "",
        legalRegistrationID: String = "",
        peppolEndpointID: String = "",
        peppolSchemeID: String = ""
    ) {
        self.id = id
        self.legalName = legalName
        self.tradingName = tradingName
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.address = address
        self.vatID = vatID
        self.legalRegistrationID = legalRegistrationID
        self.peppolEndpointID = peppolEndpointID
        self.peppolSchemeID = peppolSchemeID
    }

    public var hasVATID: Bool { !vatID.trimmed.isEmpty }

    /// The ISO 3166 prefix of the VAT id ("FI12345678" → "FI"), uppercased.
    public var vatCountryPrefix: String {
        String(vatID.trimmed.prefix(2)).uppercased()
    }

    public var displayName: String {
        tradingName.isEmpty ? legalName : tradingName
    }

    /// The participant identifier as it must appear on the wire: a legacy Finnish
    /// scheme is upgraded to the mandated `0216` (value unchanged), so an old
    /// `0037:0037…` address never leaks into a transmitted document or lookup.
    /// Empty parts stay empty.
    public var peppolParticipant: PeppolID {
        PeppolParticipant.normalized(PeppolID(schemeID: peppolSchemeID, endpointID: peppolEndpointID))
    }
}

extension String {
    public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

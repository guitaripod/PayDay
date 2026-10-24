import Foundation

/// A Peppol participant identifier: the `schemeID` (EAS / ISO 6523 ICD code) and
/// the value it qualifies, e.g. scheme `0216` + value `003735595497` for a
/// Finnish OVT code. This is the address a document is routed to on Peppol.
public struct PeppolID: Sendable, Equatable, Hashable {
    public let schemeID: String
    public let endpointID: String

    public init(schemeID: String, endpointID: String) {
        self.schemeID = schemeID.trimmed
        self.endpointID = endpointID.trimmed
    }

    /// Parses the `scheme:value` form used in the UI, splitting on the first
    /// colon. Returns an empty id when there is no colon.
    public init(parsing raw: String) {
        let input = raw.trimmed
        guard let colon = input.firstIndex(of: ":") else {
            self.init(schemeID: "", endpointID: "")
            return
        }
        self.init(
            schemeID: String(input[..<colon]),
            endpointID: String(input[input.index(after: colon)...]))
    }

    public var isEmpty: Bool { schemeID.isEmpty || endpointID.isEmpty }

    /// The `scheme:value` form shown in the UI, e.g. `0216:003735595497`.
    public var wire: String { "\(schemeID):\(endpointID)" }
}

/// A Peppol Electronic Address Scheme (EAS / ISO 6523 ICD) — the `schemeID` that
/// qualifies a participant identifier. Only the schemes Pay Day recognises for
/// guidance are catalogued; the field accepts any code, so this is a help-and-
/// validate catalogue, not a whitelist.
public struct PeppolScheme: Sendable, Equatable, Hashable {
    public let code: String
    public let name: String
    public let label: String
    /// The ISO 3166 country the scheme is specific to, when it is national.
    public let country: String?
    /// Removed from the OpenPeppol participant-identifier code list — must not be
    /// used for new routing addresses (kept only to recognise & upgrade old data).
    public let isLegacy: Bool

    public init(code: String, name: String, label: String, country: String?, isLegacy: Bool) {
        self.code = code
        self.name = name
        self.label = label
        self.country = country
        self.isLegacy = isLegacy
    }
}

/// An advisory hint about a Peppol participant identifier — never blocks issuing,
/// only guides the user toward a compliant address. Carries a ready-to-apply
/// ``PeppolID`` when Pay Day can compute the correct value.
public struct PeppolAdvisory: Sendable, Equatable {
    public enum Level: Sendable, Equatable { case info, warning }
    public let level: Level
    public let message: String
    public let suggestion: PeppolID?

    public init(level: Level, message: String, suggestion: PeppolID? = nil) {
        self.level = level
        self.message = message
        self.suggestion = suggestion
    }
}

/// Peppol participant-identifier logic: scheme catalogue, Finnish OVT derivation,
/// legacy-scheme normalisation, and country-aware advisories.
///
/// Finland is the load-bearing case: the Finnish Peppol Authority (State
/// Treasury / Valtiokonttori) mandates scheme `0216` (FI:OVT2, "OVT code"); the
/// old `0037` / `0212` / `0213` schemes were removed from the participant-
/// identifier code list per 31.12.2024. A Finnish OVT value is `0037` + the
/// 8-digit business ID (Y-tunnus without the hyphen) + an optional 5-char
/// suffix — the fixed `0037` prefix stays inside the value; only the scheme
/// wrapper changes (`0037:0037…` → `0216:0037…`).
public enum PeppolParticipant {
    public static let schemes: [PeppolScheme] = [
        PeppolScheme(code: "0216", name: "FI:OVT2", label: "Finnish OVT code", country: "FI", isLegacy: false),
        PeppolScheme(code: "0037", name: "FI:OVT", label: "Finnish LY-tunnus / OVT (legacy)", country: "FI", isLegacy: true),
        PeppolScheme(code: "0212", name: "FI:ORG", label: "Finnish business ID (legacy for routing)", country: "FI", isLegacy: true),
        PeppolScheme(code: "0213", name: "FI:VAT", label: "Finnish VAT (legacy for routing)", country: "FI", isLegacy: true),
        PeppolScheme(code: "0215", name: "FI:NSI", label: "Finnish NSI (legacy)", country: "FI", isLegacy: true),
        PeppolScheme(code: "0208", name: "BE:EN", label: "Belgian enterprise number", country: "BE", isLegacy: false),
        PeppolScheme(code: "9925", name: "BE:VAT", label: "Belgian VAT", country: "BE", isLegacy: false),
        PeppolScheme(code: "9930", name: "DE:VAT", label: "German VAT", country: "DE", isLegacy: false),
        PeppolScheme(code: "9944", name: "NL:VAT", label: "Dutch VAT", country: "NL", isLegacy: false),
        PeppolScheme(code: "0106", name: "NL:KVK", label: "Dutch Chamber of Commerce (KvK)", country: "NL", isLegacy: false),
        PeppolScheme(code: "0007", name: "SE:ORGNR", label: "Swedish organisation number", country: "SE", isLegacy: false),
        PeppolScheme(code: "9955", name: "SE:VAT", label: "Swedish VAT", country: "SE", isLegacy: false),
        PeppolScheme(code: "0192", name: "NO:ORG", label: "Norwegian organisation number", country: "NO", isLegacy: false),
        PeppolScheme(code: "0184", name: "DK:CVR", label: "Danish CVR", country: "DK", isLegacy: false),
        PeppolScheme(code: "0002", name: "FR:SIRENE", label: "French SIRENE", country: "FR", isLegacy: false),
        PeppolScheme(code: "0009", name: "FR:SIRET", label: "French SIRET", country: "FR", isLegacy: false),
        PeppolScheme(code: "9957", name: "FR:VAT", label: "French VAT", country: "FR", isLegacy: false),
        PeppolScheme(code: "9906", name: "IT:VAT", label: "Italian VAT", country: "IT", isLegacy: false),
        PeppolScheme(code: "0088", name: "GLN", label: "GLN (GS1)", country: nil, isLegacy: false),
    ]

    public static func scheme(for code: String) -> PeppolScheme? {
        let c = code.trimmed
        return schemes.first { $0.code == c }
    }

    /// The mandated Finnish OVT participant identifier derived from a Finnish
    /// business ID (Y-tunnus, e.g. `3559549-7`) or Finnish VAT number (e.g.
    /// `FI35595497`) — both reduce to the same 8 business-ID digits. Returns nil
    /// unless exactly 8 digits remain. An optional org-unit suffix (up to 5
    /// chars) is appended verbatim, uppercased.
    public static func finnishOVT(fromBusinessID id: String, suffix: String = "") -> PeppolID? {
        let digits = id.filter(\.isNumber)
        guard digits.count == 8 else { return nil }
        return PeppolID(schemeID: "0216", endpointID: "0037" + digits + suffix.trimmed.uppercased())
    }

    /// Upgrades a legacy Finnish participant identifier to the mandated scheme
    /// WITHOUT changing the value — the only silent rewrite that is provably
    /// lossless: `0037:0037…` → `0216:0037…` (the OVT value already carries the
    /// fixed `0037` prefix, so this swaps the scheme wrapper only). Every other
    /// input is returned unchanged; schemes whose value would have to change
    /// (`0212` business ID, `0213` VAT) are left for interactive guidance.
    public static func normalized(_ id: PeppolID) -> PeppolID {
        if id.schemeID == "0037" && id.endpointID.hasPrefix("0037") {
            return PeppolID(schemeID: "0216", endpointID: id.endpointID)
        }
        return id
    }

    /// Whether a value is a well-formed Finnish OVT: `0037` + 8 business-ID
    /// digits + an optional suffix of up to 5 alphanumerics.
    public static func isValidFinnishOVT(_ value: String) -> Bool {
        let v = value.trimmed.uppercased()
        guard v.hasPrefix("0037") else { return false }
        let rest = v.dropFirst(4)
        guard rest.count >= 8 else { return false }
        let business = rest.prefix(8)
        guard business.allSatisfy(\.isNumber) else { return false }
        let suffix = rest.dropFirst(8)
        guard suffix.count <= 5 else { return false }
        return suffix.allSatisfy { $0.isNumber || ($0.isLetter && $0.isASCII) }
    }

    /// A country-aware advisory for a participant identifier, or nil when it is
    /// already compliant (or empty with nothing to suggest). For Finnish parties
    /// this steers legacy/blank/malformed input toward a `0216` OVT and, where
    /// possible, offers the corrected id to apply in one tap.
    public static func advisory(
        schemeID: String, endpointID: String,
        countryCode: String, vatID: String, businessID: String
    ) -> PeppolAdvisory? {
        let id = PeppolID(schemeID: schemeID, endpointID: endpointID)
        let finnish = countryCode.trimmed.uppercased() == "FI"
            || vatID.trimmed.uppercased().hasPrefix("FI")
        let derived = derivedFinnishOVT(businessID: businessID, vatID: vatID)

        if finnish {
            if id.isEmpty {
                guard let derived else { return nil }
                return PeppolAdvisory(
                    level: .info,
                    message: "Finland uses the OVT scheme 0216. Suggested: \(derived.wire)",
                    suggestion: derived)
            }
            if id.schemeID == "0216" {
                if isValidFinnishOVT(id.endpointID) { return nil }
                let fix = finnishOVT(fromBusinessID: id.endpointID) ?? derived
                return PeppolAdvisory(
                    level: .warning,
                    message: fix.map { "A Finnish OVT is 0037 + your 8-digit business ID. Suggested: \($0.wire)" }
                        ?? "A Finnish OVT must be 0037 followed by your 8-digit business ID (e.g. 0216:003712345678).",
                    suggestion: fix)
            }
            if isLegacyFinnishScheme(id.schemeID) {
                let fix = legacyFinnishSuggestion(id) ?? derived
                return PeppolAdvisory(
                    level: .warning,
                    message: fix.map { "Finland now requires the OVT scheme 0216. Suggested: \($0.wire)" }
                        ?? "Finland now requires the OVT scheme 0216 (0037 + your 8-digit business ID).",
                    suggestion: fix)
            }
            return PeppolAdvisory(
                level: .warning,
                message: "Finnish businesses are addressed by the OVT scheme 0216 on Peppol.",
                suggestion: derived)
        }

        if !id.isEmpty && !isFourDigitScheme(id.schemeID) {
            return PeppolAdvisory(
                level: .warning,
                message: "A Peppol scheme is a 4-digit code (e.g. 9930 German VAT, 0216 Finnish OVT).",
                suggestion: nil)
        }
        return nil
    }

    private static func derivedFinnishOVT(businessID: String, vatID: String) -> PeppolID? {
        finnishOVT(fromBusinessID: businessID) ?? finnishOVT(fromBusinessID: vatID)
    }

    private static func legacyFinnishSuggestion(_ id: PeppolID) -> PeppolID? {
        if id.schemeID == "0037" && id.endpointID.hasPrefix("0037") {
            return PeppolID(schemeID: "0216", endpointID: id.endpointID)
        }
        return finnishOVT(fromBusinessID: id.endpointID)
    }

    private static func isLegacyFinnishScheme(_ code: String) -> Bool {
        ["0037", "0212", "0213", "0215"].contains(code)
    }

    private static func isFourDigitScheme(_ code: String) -> Bool {
        code.count == 4 && code.allSatisfy(\.isNumber)
    }
}

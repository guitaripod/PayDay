import Foundation

/// A country's business-to-business e-invoicing regime as it bears on a small
/// seller: which channel carries a compliant invoice, and the dated obligations
/// that phase the mandate in. Facts only — the wording shown to a user lives in
/// the app layer, where it can be localized.
public struct EInvoicingMandate: Sendable, Equatable {
    /// The channel a mandated e-invoice travels on.
    public enum Channel: Sendable, Equatable {
        /// The Peppol network — the channel Pay Day delivers on.
        case peppol
        /// A state-run clearance platform Pay Day does not submit to (KSeF, SDI, …).
        case nationalPlatform(String)
        /// No prescribed channel; structured invoices are exchanged bilaterally.
        case unspecified
    }

    /// Who an obligation reaches once its date has passed.
    public enum Scope: Sendable, Equatable {
        /// Every business must be able to receive structured e-invoices.
        case receiveAll
        /// Large (or otherwise size-thresholded) companies must issue them.
        case issueLarge
        /// Small businesses and sole traders must issue them.
        case issueSmall
        /// Every business must issue them.
        case issueAll
    }

    public struct Milestone: Sendable, Equatable {
        public let date: CalendarDate
        public let scope: Scope

        public init(date: CalendarDate, scope: Scope) {
            self.date = date
            self.scope = scope
        }
    }

    /// Where the seller stands today.
    public enum Phase: Sendable, Equatable {
        /// A small seller must already issue structured e-invoices.
        case inForce(since: CalendarDate)
        /// Some obligations apply already; the one that reaches a small seller is still ahead.
        case phasingIn(next: Milestone)
        /// Nothing applies yet; the first obligation is dated.
        case scheduled(first: Milestone)
        /// No dated business-to-business obligation.
        case noMandate
    }

    public let countryCode: String
    public let channel: Channel
    /// Ordered by date, earliest first.
    public let milestones: [Milestone]
    /// Suppliers to public bodies must already send structured e-invoices.
    public let businessToGovernmentMandatory: Bool

    public init(countryCode: String, channel: Channel, milestones: [Milestone], businessToGovernmentMandatory: Bool) {
        self.countryCode = countryCode.uppercased()
        self.channel = channel
        self.milestones = milestones.sorted { $0.date < $1.date }
        self.businessToGovernmentMandatory = businessToGovernmentMandatory
    }

    public func phase(on today: CalendarDate) -> Phase {
        let passed = milestones.filter { !(today < $0.date) }
        let upcoming = milestones.filter { today < $0.date }
        if let reached = passed.last(where: { $0.scope == .issueAll || $0.scope == .issueSmall }) {
            return .inForce(since: reached.date)
        }
        if let next = upcoming.first {
            return passed.isEmpty ? .scheduled(first: next) : .phasingIn(next: next)
        }
        return .noMandate
    }

    /// Whether Pay Day's Peppol delivery is the way to satisfy this regime.
    public var peppolSatisfies: Bool {
        channel == .peppol
    }
}

/// The catalogue of regimes Pay Day describes to its users. Countries absent
/// from the catalogue but inside the EU fall back to the union-wide rule; the
/// rest get nothing.
public enum EInvoicingMandates {
    /// VAT in the Digital Age: structured e-invoicing becomes mandatory for
    /// cross-border business-to-business supplies across the EU.
    public static let unionCrossBorder = EInvoicingMandate.Milestone(
        date: CalendarDate(year: 2030, month: 7, day: 1), scope: .issueAll)

    public static let unionMemberStates: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT",
        "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
    ]

    static let catalogue: [String: EInvoicingMandate] = {
        func date(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate { CalendarDate(year: y, month: m, day: d) }
        let entries: [EInvoicingMandate] = [
            EInvoicingMandate(countryCode: "BE", channel: .peppol, milestones: [
                .init(date: date(2026, 1, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "FR", channel: .unspecified, milestones: [
                .init(date: date(2026, 9, 1), scope: .receiveAll),
                .init(date: date(2026, 9, 1), scope: .issueLarge),
                .init(date: date(2027, 9, 1), scope: .issueSmall),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "DE", channel: .unspecified, milestones: [
                .init(date: date(2025, 1, 1), scope: .receiveAll),
                .init(date: date(2027, 1, 1), scope: .issueLarge),
                .init(date: date(2028, 1, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "NL", channel: .peppol, milestones: [], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "FI", channel: .peppol, milestones: [], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "SE", channel: .peppol, milestones: [], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "DK", channel: .peppol, milestones: [], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "NO", channel: .peppol, milestones: [
                .init(date: date(2027, 1, 1), scope: .issueAll),
                .init(date: date(2030, 1, 1), scope: .receiveAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "AT", channel: .peppol, milestones: [], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "LU", channel: .peppol, milestones: [], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "IE", channel: .peppol, milestones: [
                .init(date: date(2028, 11, 1), scope: .issueLarge),
                .init(date: date(2029, 11, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: false),
            EInvoicingMandate(countryCode: "EE", channel: .peppol, milestones: [], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "LV", channel: .peppol, milestones: [
                .init(date: date(2028, 1, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "SI", channel: .peppol, milestones: [
                .init(date: date(2028, 1, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "PT", channel: .peppol, milestones: [], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "PL", channel: .nationalPlatform("KSeF"), milestones: [
                .init(date: date(2026, 2, 1), scope: .issueLarge),
                .init(date: date(2026, 4, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "IT", channel: .nationalPlatform("SDI"), milestones: [
                .init(date: date(2019, 1, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "ES", channel: .nationalPlatform("Crea y Crece"), milestones: [
                .init(date: date(2027, 10, 1), scope: .issueLarge),
                .init(date: date(2028, 10, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "GR", channel: .nationalPlatform("myDATA"), milestones: [
                .init(date: date(2026, 3, 2), scope: .issueLarge),
                .init(date: date(2026, 10, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "RO", channel: .nationalPlatform("RO e-Factura"), milestones: [
                .init(date: date(2024, 7, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "HR", channel: .nationalPlatform("Fiskalizacija 2.0"), milestones: [
                .init(date: date(2026, 1, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
            EInvoicingMandate(countryCode: "SK", channel: .nationalPlatform("IS EFA"), milestones: [
                .init(date: date(2027, 1, 1), scope: .issueAll),
            ], businessToGovernmentMandatory: true),
        ]
        return Dictionary(uniqueKeysWithValues: entries.map { ($0.countryCode, $0) })
    }()

    /// The regime for a country, or the union-wide fallback for an EU member
    /// state that has no national one. Nil outside the EU and the catalogue.
    public static func mandate(for countryCode: String) -> EInvoicingMandate? {
        let code = countryCode.trimmed.uppercased()
        if let national = catalogue[code] { return national }
        guard unionMemberStates.contains(code) else { return nil }
        return EInvoicingMandate(countryCode: code, channel: .peppol, milestones: [unionCrossBorder], businessToGovernmentMandatory: false)
    }

    /// Whether the catalogue has a country-specific entry (as opposed to the
    /// union-wide fallback).
    public static func hasNationalEntry(for countryCode: String) -> Bool {
        catalogue[countryCode.trimmed.uppercased()] != nil
    }
}

import Testing
import Foundation
@testable import PayDayKit

@Suite("E-invoicing mandates")
struct EInvoicingMandateTests {
    private let today = CalendarDate(year: 2026, month: 9, day: 16)

    @Test("Belgium is in force for every business since 1 January 2026")
    func belgiumInForce() {
        let be = EInvoicingMandates.mandate(for: "be")
        #expect(be?.channel == .peppol)
        #expect(be?.phase(on: today) == .inForce(since: CalendarDate(year: 2026, month: 1, day: 1)))
        #expect(be?.phase(on: CalendarDate(year: 2025, month: 12, day: 31))
            == .scheduled(first: .init(date: CalendarDate(year: 2026, month: 1, day: 1), scope: .issueAll)))
    }

    @Test("France is phasing in: receiving applies, small issuers wait for September 2027")
    func francePhasing() {
        let fr = EInvoicingMandates.mandate(for: "FR")
        let next = EInvoicingMandate.Milestone(date: CalendarDate(year: 2027, month: 9, day: 1), scope: .issueSmall)
        #expect(fr?.phase(on: today) == .phasingIn(next: next))
        #expect(fr?.phase(on: CalendarDate(year: 2027, month: 9, day: 1)) == .inForce(since: next.date))
    }

    @Test("Germany reaches every business on 1 January 2028")
    func germanyPhasing() {
        let de = EInvoicingMandates.mandate(for: "DE")
        #expect(de?.phase(on: today) == .phasingIn(next: .init(date: CalendarDate(year: 2027, month: 1, day: 1), scope: .issueLarge)))
        #expect(de?.phase(on: CalendarDate(year: 2027, month: 6, day: 1)) == .phasingIn(next: .init(date: CalendarDate(year: 2028, month: 1, day: 1), scope: .issueAll)))
        #expect(de?.phase(on: CalendarDate(year: 2028, month: 1, day: 1)) == .inForce(since: CalendarDate(year: 2028, month: 1, day: 1)))
    }

    @Test("Peppol-standard countries without a dated obligation report no mandate")
    func peppolStandardCountries() {
        for code in ["NL", "FI", "SE", "DK", "AT", "LU", "EE", "PT"] {
            let mandate = EInvoicingMandates.mandate(for: code)
            #expect(mandate?.phase(on: today) == .noMandate, "\(code)")
            #expect(mandate?.peppolSatisfies == true, "\(code)")
            #expect(mandate?.businessToGovernmentMandatory == true, "\(code)")
        }
    }

    @Test("Norway's EHF mandate is scheduled for 2027 and receiving follows in 2030")
    func norwayScheduled() {
        let no = EInvoicingMandates.mandate(for: "NO")
        #expect(no?.phase(on: today) == .scheduled(first: .init(date: CalendarDate(year: 2027, month: 1, day: 1), scope: .issueAll)))
        #expect(no?.phase(on: CalendarDate(year: 2027, month: 1, day: 1)) == .inForce(since: CalendarDate(year: 2027, month: 1, day: 1)))
        #expect(EInvoicingMandates.unionMemberStates.contains("NO") == false)
    }

    @Test("Scheduled union members: Latvia and Slovenia 2028, Spain 2027/2028 via a national platform")
    func scheduledMembers() {
        #expect(EInvoicingMandates.mandate(for: "LV")?.phase(on: today) == .scheduled(first: .init(date: CalendarDate(year: 2028, month: 1, day: 1), scope: .issueAll)))
        #expect(EInvoicingMandates.mandate(for: "SI")?.phase(on: today) == .scheduled(first: .init(date: CalendarDate(year: 2028, month: 1, day: 1), scope: .issueAll)))
        let es = EInvoicingMandates.mandate(for: "ES")
        #expect(es?.channel == .nationalPlatform("Crea y Crece"))
        #expect(es?.phase(on: today) == .scheduled(first: .init(date: CalendarDate(year: 2027, month: 10, day: 1), scope: .issueLarge)))
        #expect(es?.phase(on: CalendarDate(year: 2028, month: 10, day: 1)) == .inForce(since: CalendarDate(year: 2028, month: 10, day: 1)))
    }

    @Test("Ireland is scheduled, not yet in force")
    func irelandScheduled() {
        let ie = EInvoicingMandates.mandate(for: "IE")
        #expect(ie?.phase(on: today) == .scheduled(first: .init(date: CalendarDate(year: 2028, month: 11, day: 1), scope: .issueLarge)))
    }

    @Test("National clearance platforms are in force but not satisfied by Peppol")
    func nationalPlatforms() {
        let pl = EInvoicingMandates.mandate(for: "PL")
        #expect(pl?.channel == .nationalPlatform("KSeF"))
        #expect(pl?.phase(on: today) == .inForce(since: CalendarDate(year: 2026, month: 4, day: 1)))
        #expect(pl?.peppolSatisfies == false)
        let it = EInvoicingMandates.mandate(for: "IT")
        #expect(it?.channel == .nationalPlatform("SDI"))
        #expect(it?.peppolSatisfies == false)
        #expect(EInvoicingMandates.mandate(for: "GR")?.phase(on: today) == .phasingIn(next: .init(date: CalendarDate(year: 2026, month: 10, day: 1), scope: .issueAll)))
        #expect(EInvoicingMandates.mandate(for: "RO")?.phase(on: today) == .inForce(since: CalendarDate(year: 2024, month: 7, day: 1)))
        #expect(EInvoicingMandates.mandate(for: "HR")?.phase(on: today) == .inForce(since: CalendarDate(year: 2026, month: 1, day: 1)))
        #expect(EInvoicingMandates.mandate(for: "SK")?.phase(on: today) == .scheduled(first: .init(date: CalendarDate(year: 2027, month: 1, day: 1), scope: .issueAll)))
    }

    @Test("EU members without a national entry fall back to the union-wide 2030 rule")
    func unionFallback() {
        for code in ["CZ", "LT", "HU", "BG", "CY", "MT"] {
            let fallback = EInvoicingMandates.mandate(for: code)
            #expect(EInvoicingMandates.hasNationalEntry(for: code) == false, "\(code)")
            #expect(fallback?.phase(on: today) == .scheduled(first: EInvoicingMandates.unionCrossBorder), "\(code)")
            #expect(fallback?.channel == .peppol, "\(code)")
        }
    }

    @Test("Outside the EU there is nothing to say")
    func outsideUnion() {
        #expect(EInvoicingMandates.mandate(for: "US") == nil)
        #expect(EInvoicingMandates.mandate(for: "") == nil)
        #expect(EInvoicingMandates.mandate(for: "GB") == nil)
    }

    @Test("Milestones are kept in date order regardless of declaration order")
    func milestonesSorted() {
        let m = EInvoicingMandate(countryCode: "xx", channel: .unspecified, milestones: [
            .init(date: CalendarDate(year: 2028, month: 1, day: 1), scope: .issueAll),
            .init(date: CalendarDate(year: 2025, month: 1, day: 1), scope: .receiveAll),
        ], businessToGovernmentMandatory: false)
        #expect(m.countryCode == "XX")
        #expect(m.milestones.first?.scope == .receiveAll)
        #expect(m.phase(on: today) == .phasingIn(next: .init(date: CalendarDate(year: 2028, month: 1, day: 1), scope: .issueAll)))
    }
}

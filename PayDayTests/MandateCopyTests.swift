import Testing
import Foundation
@testable import PayDay
import PayDayKit

/// The dashboard card's country → copy resolution, pinned to a fixed date so the
/// phase logic cannot drift with the calendar.
@Suite("Mandate card copy")
@MainActor
struct MandateCopyTests {
    private let today = CalendarDate(year: 2026, month: 9, day: 16)
    private let english = Locale(identifier: "en_US")

    @Test("Belgium: urgent, and a free user is sent to the paywall for Peppol")
    func belgiumFreeUser() {
        let card = MandateCopy.card(countryCode: "BE", isPro: false, peppolConfigured: false, today: today, locale: english)
        #expect(card?.tone == .urgent)
        #expect(card?.title == "E-invoicing in Belgium")
        #expect(card?.deadline == nil)
        if case .unlockPro(let reason)? = card?.action {
            #expect(reason.contains("Belgium"))
        } else {
            Issue.record("expected a paywall action")
        }
    }

    @Test("Belgium: a Pro user without a Peppol ID is sent to Peppol setup, with one to business settings")
    func belgiumProUser() {
        #expect(MandateCopy.card(countryCode: "BE", isPro: true, peppolConfigured: false, today: today, locale: english)?.action == .openPeppolSettings)
        #expect(MandateCopy.card(countryCode: "BE", isPro: true, peppolConfigured: true, today: today, locale: english)?.action == .openBusinessSettings)
    }

    @Test("France: phasing in with a dated next step and a Factur-X call to action")
    func france() {
        let card = MandateCopy.card(countryCode: "fr", isPro: false, peppolConfigured: false, today: today, locale: english)
        #expect(card?.tone == .active)
        #expect(card?.deadline?.contains("2027") == true)
        #expect(card?.actionTitle == "Unlock Factur-X e-invoices")
    }

    @Test("A national clearance platform gets no call to action")
    func nationalPlatform() {
        let card = MandateCopy.card(countryCode: "PL", isPro: false, peppolConfigured: false, today: today, locale: english)
        #expect(card?.action == .informationOnly)
        #expect(card?.actionTitle == nil)
        #expect(card?.body.contains("KSeF") == true)
    }

    @Test("Outside the EU there is no card and no welcome line")
    func outsideUnion() {
        #expect(MandateCopy.card(countryCode: "US", isPro: false, peppolConfigured: false, today: today, locale: english) == nil)
        #expect(MandateCopy.welcomeLine(countryCode: "US", today: today, locale: english) == nil)
        #expect(MandateCopy.welcomeLine(countryCode: "", today: today, locale: english) == nil)
    }

    @Test("Welcome line leads with the mandate where there is one, and stays quiet otherwise")
    func welcomeLine() {
        #expect(MandateCopy.welcomeLine(countryCode: "BE", today: today, locale: english) == "Belgium: e-invoicing is mandatory for every business since January 1, 2026.")
        #expect(MandateCopy.welcomeLine(countryCode: "NO", today: today, locale: english)?.contains("starts January 1, 2027") == true)
        #expect(MandateCopy.welcomeLine(countryCode: "NL", today: today, locale: english) == nil)
        #expect(MandateCopy.welcomeLine(countryCode: "IT", today: today, locale: english) == nil)
    }
}

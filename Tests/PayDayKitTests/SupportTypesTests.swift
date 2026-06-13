import Testing
import Foundation
@testable import PayDayKit

@Suite("Number sequence, dates, round-trips")
struct SupportTypesTests {
    @Test("Sequence template renders year and zero-padded counter")
    func numberTemplate() {
        let date = CalendarDate(year: 2026, month: 6, day: 13)
        var seq = NumberSequence(type: .invoice, template: "INV-{YYYY}-{seq:04}", nextValue: 7)
        #expect(seq.peek(on: date) == "INV-2026-0007")
        #expect(seq.advance(on: date) == "INV-2026-0007")
        #expect(seq.nextValue == 8)
        #expect(seq.peek(on: date) == "INV-2026-0008")
    }

    @Test("Unpadded and month tokens")
    func templateVariants() {
        let date = CalendarDate(year: 2026, month: 3, day: 9)
        #expect(NumberSequence.render(template: "{YY}{MM}-{seq}", sequence: 42, date: date) == "2603-42")
        #expect(NumberSequence.render(template: "Q-{seq:06}", sequence: 1, date: date) == "Q-000001")
    }

    @Test("CalendarDate wire formats")
    func dateFormats() {
        let date = CalendarDate(year: 2026, month: 6, day: 1)
        #expect(date.ciiString == "20260601")
        #expect(date.iso8601 == "2026-06-01")
        #expect(date.adding(days: 14).iso8601 == "2026-06-15")
        #expect(CalendarDate(year: 2026, month: 1, day: 1) < CalendarDate(year: 2026, month: 1, day: 2))
    }

    @Test("Invoice round-trips through JSON unchanged")
    func codableRoundTrip() throws {
        let original = DemoData.sampleIntraCommunityInvoice()
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(Invoice.self, from: data)
        #expect(restored == original)
        #expect(restored.totals().summary == original.totals().summary)
    }

    @Test("Decoding tolerates missing fields (schema evolution)")
    func tolerantDecode() throws {
        // An older persisted row, before fields like buyerReference existed.
        let json = #"{"id":"old-1","type":"invoice","number":"INV-OLD-1","currency":{"code":"EUR","minorUnitDigits":2}}"#
        let invoice = try JSONDecoder().decode(Invoice.self, from: Data(json.utf8))
        #expect(invoice.number == "INV-OLD-1")
        #expect(invoice.buyerReference == "")
        #expect(invoice.status == .draft)
        #expect(invoice.lines.isEmpty)
        #expect(invoice.currency.code == "EUR")
    }

    @Test("VAT category rules")
    func vatCategoryRules() {
        #expect(VATCategory.standard.allowsPositiveRate)
        #expect(!VATCategory.intraCommunity.allowsPositiveRate)
        #expect(VATCategory.reverseCharge.requiresBothVATIDs)
        #expect(VATCategory.exempt.requiresExemptionReason)
        #expect(!VATCategory.standard.requiresExemptionReason)
    }
}

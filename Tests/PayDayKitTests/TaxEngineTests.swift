import Testing
import Foundation
@testable import PayDayKit

@Suite("Tax engine — EN 16931 summation")
struct TaxEngineTests {
    @Test("Sample invoice totals are exact")
    func sampleTotals() {
        let totals = DemoData.sampleInvoice().totals()
        let s = totals.summary
        #expect(totals.lineNets.map(\.minorUnits) == [304000, 216000])
        #expect(s.lineTotal.minorUnits == 520000)
        #expect(s.taxExclusiveTotal.minorUnits == 520000)
        #expect(s.taxTotal.minorUnits == 132600)
        #expect(s.taxInclusiveTotal.minorUnits == 652600)
        #expect(s.payableAmount.minorUnits == 652600)
        #expect(totals.breakdowns.count == 1)
        #expect(totals.breakdowns[0].category == .standard)
        #expect(totals.breakdowns[0].ratePercent == Decimal(string: "25.5"))
    }

    @Test("VAT is rounded on the group sum, not per line")
    func roundTheSum() {
        let lines = (0..<3).map {
            LineItem(id: "l\($0)", name: "x", quantity: 1, unitPrice: Decimal(string: "1.10")!,
                     vatCategory: .standard, vatRatePercent: Decimal(string: "8.5")!)
        }
        let invoice = makeInvoice(lines: lines)
        let totals = invoice.totals()
        #expect(totals.summary.lineTotal.minorUnits == 330)
        #expect(totals.breakdowns.count == 1)
        #expect(totals.breakdowns[0].taxableBase.minorUnits == 330)
        #expect(totals.breakdowns[0].taxAmount.minorUnits == 28)
        #expect(totals.summary.taxInclusiveTotal.minorUnits == 358)
    }

    @Test("Category taxable base equals the sum of rounded line nets")
    func baseEqualsSumOfLineNets() {
        let lines = [
            LineItem(id: "a", name: "a", quantity: 1, unitPrice: Decimal(string: "10.005")!,
                     vatCategory: .standard, vatRatePercent: 24),
            LineItem(id: "b", name: "b", quantity: 1, unitPrice: Decimal(string: "10.005")!,
                     vatCategory: .standard, vatRatePercent: 24),
        ]
        let totals = makeInvoice(lines: lines).totals()
        let sumOfLineNets = totals.lineNets.reduce(0) { $0 + $1.minorUnits }
        #expect(totals.breakdowns[0].taxableBase.minorUnits == sumOfLineNets)
        #expect(sumOfLineNets == 2002)
    }

    @Test("Mixed VAT rates produce separate breakdown groups")
    func mixedRates() {
        let lines = [
            LineItem(id: "a", name: "std", quantity: 1, unitPrice: 100, vatCategory: .standard, vatRatePercent: 24),
            LineItem(id: "b", name: "red", quantity: 1, unitPrice: 100, vatCategory: .standard, vatRatePercent: 10),
            LineItem(id: "c", name: "ic", quantity: 1, unitPrice: 100, vatCategory: .intraCommunity, vatRatePercent: 0),
        ]
        let totals = makeInvoice(lines: lines, sellerVAT: "FI1", buyerVAT: "DE1").totals()
        #expect(totals.breakdowns.count == 3)
        #expect(totals.summary.taxTotal.minorUnits == 3400)
        let ic = totals.breakdowns.first { $0.category == .intraCommunity }
        #expect(ic?.taxAmount.minorUnits == 0)
        #expect(ic?.exemptionReason == "Intra-Community supply")
    }

    @Test("Per-line discount reduces the net")
    func discount() {
        let line = LineItem(id: "d", name: "x", quantity: 1, unitPrice: 2400, discountPercent: 10,
                            vatCategory: .standard, vatRatePercent: 25)
        let totals = makeInvoice(lines: [line]).totals()
        #expect(totals.lineNets[0].minorUnits == 216000)
    }

    @Test("Document allowance and charge fold into the exclusive total")
    func adjustments() {
        let line = LineItem(id: "x", name: "x", quantity: 1, unitPrice: 1000, vatCategory: .standard, vatRatePercent: 20)
        var invoice = makeInvoice(lines: [line])
        invoice.adjustments = [
            DocumentAdjustment(id: "disc", isCharge: false, reason: "Loyalty", amount: 100, vatCategory: .standard, vatRatePercent: 20),
            DocumentAdjustment(id: "ship", isCharge: true, reason: "Rush", amount: 50, vatCategory: .standard, vatRatePercent: 20),
        ]
        let totals = invoice.totals()
        #expect(totals.summary.lineTotal.minorUnits == 100000)
        #expect(totals.summary.allowanceTotal.minorUnits == 10000)
        #expect(totals.summary.chargeTotal.minorUnits == 5000)
        #expect(totals.summary.taxExclusiveTotal.minorUnits == 95000)
        #expect(totals.summary.taxTotal.minorUnits == 19000)
    }

    @Test("Prepaid amount reduces the payable amount")
    func prepaid() {
        let line = LineItem(id: "x", name: "x", quantity: 1, unitPrice: 1000, vatCategory: .standard, vatRatePercent: 20)
        var invoice = makeInvoice(lines: [line])
        invoice.prepaidMinorUnits = 50000
        let s = invoice.totals().summary
        #expect(s.taxInclusiveTotal.minorUnits == 120000)
        #expect(s.payableAmount.minorUnits == 70000)
    }

    private func makeInvoice(lines: [LineItem], sellerVAT: String = "FI1", buyerVAT: String = "FI2") -> Invoice {
        Invoice(
            id: "t", type: .invoice, number: "INV-1",
            issueDate: CalendarDate(year: 2026, month: 1, day: 1),
            dueDate: CalendarDate(year: 2026, month: 1, day: 31),
            currency: .eur,
            seller: Party(id: "s", legalName: "S", address: PostalAddress(countryCode: "FI"), vatID: sellerVAT),
            buyer: Party(id: "b", legalName: "B", address: PostalAddress(countryCode: "DE"), vatID: buyerVAT),
            lines: lines)
    }
}

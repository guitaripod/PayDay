import Testing
import Foundation
@testable import PayDayKit

@Suite("EN 16931 validator")
struct InvoiceValidatorTests {
    @Test("Both sample invoices are compliant")
    func samplesPass() {
        #expect(InvoiceValidator.isCompliant(DemoData.sampleInvoice()))
        #expect(InvoiceValidator.isCompliant(DemoData.sampleIntraCommunityInvoice()))
    }

    @Test("Missing invoice number fails BR-02")
    func missingNumber() {
        var doc = DemoData.sampleInvoice()
        doc.number = ""
        let issues = InvoiceValidator.validate(doc)
        #expect(issues.contains { $0.rule == "BR-02" && $0.severity == .error })
        #expect(!InvoiceValidator.isCompliant(doc))
    }

    @Test("Standard rate without seller VAT fails BR-S-02")
    func standardNeedsSellerVAT() {
        var doc = DemoData.sampleInvoice()
        doc.seller.vatID = ""
        let issues = InvoiceValidator.validate(doc)
        #expect(issues.contains { $0.rule == "BR-S-02" && $0.severity == .error })
    }

    @Test("Standard rate must be greater than zero")
    func standardNeedsPositiveRate() {
        var doc = DemoData.sampleInvoice()
        doc.lines = doc.lines.map {
            var l = $0; l.vatRatePercent = 0; return l
        }
        let issues = InvoiceValidator.validate(doc)
        #expect(issues.contains { $0.rule == "BR-S-05" && $0.severity == .error })
    }

    @Test("Intra-community requires both VAT identifiers")
    func intraCommunityNeedsBothVAT() {
        var doc = DemoData.sampleIntraCommunityInvoice()
        doc.buyer.vatID = ""
        let issues = InvoiceValidator.validate(doc)
        #expect(issues.contains { $0.rule == "BR-K-03" && $0.severity == .error })
    }

    @Test("Missing country code fails BR-09 / BR-11")
    func missingCountry() {
        var doc = DemoData.sampleInvoice()
        doc.seller.address.countryCode = ""
        let issues = InvoiceValidator.validate(doc)
        #expect(issues.contains { $0.rule == "BR-09" && $0.severity == .error })
    }

    @Test("Due date before issue date is a warning, not a block")
    func dueBeforeIssue() {
        var doc = DemoData.sampleInvoice()
        doc.dueDate = CalendarDate(year: 2026, month: 5, day: 1)
        let issues = InvoiceValidator.validate(doc)
        #expect(issues.contains { $0.rule == "BR-CO-25" && $0.severity == .warning })
        #expect(InvoiceValidator.isCompliant(doc))
    }
}

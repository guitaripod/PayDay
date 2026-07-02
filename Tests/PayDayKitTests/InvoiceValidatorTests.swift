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

    @Test("Seller with no VAT id, registration or seller id fails BR-CO-26")
    func sellerMustBeIdentifiable() {
        var doc = DemoData.sampleInvoice()
        doc.seller.vatID = ""
        doc.seller.legalRegistrationID = ""
        doc.seller.peppolEndpointID = ""
        let issues = InvoiceValidator.validate(doc)
        #expect(issues.contains { $0.rule == "BR-CO-26" && $0.severity == .error })
        #expect(!InvoiceValidator.isCompliant(doc))
    }

    @Test("Missing buyer and order reference is an advisory Peppol R003 warning, not a block")
    func peppolReferenceWarning() {
        var doc = DemoData.sampleInvoice()
        doc.buyerReference = ""
        doc.purchaseOrderReference = ""
        let issues = InvoiceValidator.validate(doc)
        #expect(issues.contains { $0.rule == "PEPPOL-EN16931-R003" && $0.severity == .warning })
        #expect(InvoiceValidator.isCompliant(doc))
    }

    @Test("Missing Peppol participants block transmission but not document compliance")
    func peppolEndpointPreflight() {
        var doc = DemoData.sampleInvoice()
        doc.seller.peppolEndpointID = ""
        doc.seller.peppolSchemeID = ""
        doc.buyer.peppolEndpointID = ""
        doc.buyer.peppolSchemeID = ""
        let issues = InvoiceValidator.peppolIssues(doc)
        #expect(issues.contains { $0.rule == "PEPPOL-EN16931-R020" && $0.severity == .error })
        #expect(issues.contains { $0.rule == "PEPPOL-EN16931-R010" && $0.severity == .error })
        #expect(InvoiceValidator.isCompliant(doc))
    }

    @Test("Buyer without a Peppol participant is flagged, seller with one is not")
    func peppolBuyerOnlyMissing() {
        let doc = DemoData.sampleInvoice()
        let issues = InvoiceValidator.peppolIssues(doc)
        #expect(issues.contains { $0.rule == "PEPPOL-EN16931-R010" })
        #expect(!issues.contains { $0.rule == "PEPPOL-EN16931-R020" })
        #expect(InvoiceValidator.peppolIssues(DemoData.sampleIntraCommunityInvoice()).isEmpty)
    }
}

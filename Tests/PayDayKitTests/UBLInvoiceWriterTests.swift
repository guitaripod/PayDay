import Testing
import Foundation
@testable import PayDayKit

@Suite("UBL / Peppol BIS 3.0 writer")
struct UBLInvoiceWriterTests {
    @Test("Peppol customization and profile identifiers")
    func customization() throws {
        let xml = try UBLInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(xml.contains("<Invoice"))
        #expect(xml.contains(PeppolIdentifiers.customizationID))
        #expect(xml.contains(PeppolIdentifiers.profileID))
        #expect(xml.contains("<cbc:ID>INV-2026-0007</cbc:ID>"))
        #expect(xml.contains("<cbc:InvoiceTypeCode>380</cbc:InvoiceTypeCode>"))
        #expect(xml.contains("<cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>"))
    }

    @Test("Legal monetary total and tax subtotals")
    func totals() throws {
        let xml = try UBLInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(xml.contains("<cbc:LineExtensionAmount currencyID=\"EUR\">5200.00</cbc:LineExtensionAmount>"))
        #expect(xml.contains("<cbc:TaxInclusiveAmount currencyID=\"EUR\">6526.00</cbc:TaxInclusiveAmount>"))
        #expect(xml.contains("<cbc:PayableAmount currencyID=\"EUR\">6526.00</cbc:PayableAmount>"))
        #expect(xml.contains("<cbc:TaxAmount currencyID=\"EUR\">1326.00</cbc:TaxAmount>"))
        #expect(xml.contains("<cac:TaxScheme>"))
    }

    @Test("Endpoint id and party tax scheme")
    func parties() throws {
        let xml = try UBLInvoiceWriter().xml(for: DemoData.sampleIntraCommunityInvoice())
        #expect(xml.contains("<cbc:EndpointID schemeID=\"0037\">12345678</cbc:EndpointID>"))
        #expect(xml.contains("<cbc:EndpointID schemeID=\"9930\">DE123456789</cbc:EndpointID>"))
        #expect(!xml.contains("0037:12345678"))
        #expect(xml.contains("<cbc:CompanyID>DE123456789</cbc:CompanyID>"))
        #expect(xml.contains("<cbc:TaxExemptionReason>Intra-Community supply</cbc:TaxExemptionReason>"))
    }

    @Test("Credit note uses the CreditNote root and 381 type code")
    func creditNote() throws {
        var doc = DemoData.sampleInvoice()
        doc.type = .creditNote
        doc.precedingInvoiceNumber = "INV-2026-0007"
        let xml = try UBLInvoiceWriter().xml(for: doc)
        #expect(xml.contains("<CreditNote"))
        #expect(xml.contains("<cbc:CreditNoteTypeCode>381</cbc:CreditNoteTypeCode>"))
        #expect(xml.contains("<cac:CreditNoteLine>"))
        #expect(xml.contains("<cbc:CreditedQuantity"))
        #expect(xml.contains("<cac:BillingReference>"))
    }

    @Test("Discounted line emits a reconciling line allowance (PEPPOL-EN16931-R120)")
    func lineDiscountAllowance() throws {
        let xml = try UBLInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(xml.contains("<cbc:ChargeIndicator>false</cbc:ChargeIndicator>"))
        #expect(xml.contains("<cbc:AllowanceChargeReason>Discount</cbc:AllowanceChargeReason>"))
    }

    @Test("Intra-community supply carries delivery date and deliver-to country (BR-IC-11/12)")
    func intraCommunityDelivery() throws {
        let xml = try UBLInvoiceWriter().xml(for: DemoData.sampleIntraCommunityInvoice())
        #expect(xml.contains("<cac:Delivery>"))
        #expect(xml.contains("<cbc:ActualDeliveryDate>"))
        #expect(xml.contains("<cac:DeliveryLocation>"))
        #expect(xml.contains("<cbc:IdentificationCode>DE</cbc:IdentificationCode>"))
    }

    @Test("Output is well-formed XML")
    func wellFormed() throws {
        let xml = try UBLInvoiceWriter().xml(for: DemoData.sampleInvoice())
        let parser = XMLParser(data: Data(xml.utf8))
        #expect(parser.parse())
    }
}

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
        #expect(xml.contains("<cbc:EndpointID schemeID=\"0216\">003712345678</cbc:EndpointID>"))
        #expect(xml.contains("<cbc:EndpointID schemeID=\"9930\">DE123456789</cbc:EndpointID>"))
        #expect(xml.contains("<cbc:CompanyID>DE123456789</cbc:CompanyID>"))
        #expect(xml.contains("<cbc:TaxExemptionReason>Intra-Community supply</cbc:TaxExemptionReason>"))
    }

    @Test("Legacy Finnish 0037 OVT is upgraded to the mandated 0216 on the wire")
    func finnishSchemeNormalization() throws {
        var doc = DemoData.sampleInvoice()
        doc.seller.peppolSchemeID = "0037"
        doc.seller.peppolEndpointID = "003735595497"
        let xml = try UBLInvoiceWriter().xml(for: doc)
        #expect(xml.contains("<cbc:EndpointID schemeID=\"0216\">003735595497</cbc:EndpointID>"))
        #expect(!xml.contains("schemeID=\"0037\""))
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

    @Test("IBAN is emitted without the user's display spaces (BT-84)")
    func ibanNormalised() throws {
        let xml = try UBLInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(xml.contains("<cbc:ID>FI2112345600000785</cbc:ID>"))
        #expect(!xml.contains("FI21 1234"))
    }

    @Test("Intra-community supply carries delivery date and deliver-to country (BR-IC-11/12)")
    func intraCommunityDelivery() throws {
        let xml = try UBLInvoiceWriter().xml(for: DemoData.sampleIntraCommunityInvoice())
        #expect(xml.contains("<cac:Delivery>"))
        #expect(xml.contains("<cbc:ActualDeliveryDate>"))
        #expect(xml.contains("<cac:DeliveryLocation>"))
        #expect(xml.contains("<cbc:IdentificationCode>DE</cbc:IdentificationCode>"))
    }

    @Test("Document allowances and charges are emitted and reconcile with BT-107/BT-108")
    func documentAllowanceCharge() throws {
        var doc = DemoData.sampleInvoice()
        doc.adjustments = [
            DocumentAdjustment(id: "a1", isCharge: false, reason: "Loyalty discount", amount: 100, vatCategory: .standard, vatRatePercent: 25.5),
            DocumentAdjustment(id: "a2", isCharge: true, reason: "Freight", amount: 20, vatCategory: .standard, vatRatePercent: 25.5),
        ]
        let xml = try UBLInvoiceWriter().xml(for: doc)
        #expect(xml.contains("<cbc:AllowanceChargeReason>Loyalty discount</cbc:AllowanceChargeReason>"))
        #expect(xml.contains("<cbc:AllowanceChargeReason>Freight</cbc:AllowanceChargeReason>"))
        #expect(xml.contains("<cbc:Amount currencyID=\"EUR\">100.00</cbc:Amount>"))
        #expect(xml.contains("<cbc:Amount currencyID=\"EUR\">20.00</cbc:Amount>"))
        #expect(xml.contains("<cbc:ChargeIndicator>true</cbc:ChargeIndicator>"))
        #expect(xml.contains("<cbc:AllowanceTotalAmount currencyID=\"EUR\">100.00</cbc:AllowanceTotalAmount>"))
        #expect(xml.contains("<cbc:ChargeTotalAmount currencyID=\"EUR\">20.00</cbc:ChargeTotalAmount>"))
        let allowanceChargeIndex = try #require(xml.range(of: "<cac:AllowanceCharge>"))
        let taxTotalIndex = try #require(xml.range(of: "<cac:TaxTotal>"))
        #expect(allowanceChargeIndex.lowerBound < taxTotalIndex.lowerBound)
    }

    @Test("Credit note omits cbc:DueDate and carries BT-9 as cbc:PaymentDueDate")
    func creditNoteDueDate() throws {
        var doc = DemoData.sampleInvoice()
        doc.type = .creditNote
        doc.precedingInvoiceNumber = "INV-2026-0007"
        let xml = try UBLInvoiceWriter().xml(for: doc)
        #expect(!xml.contains("<cbc:DueDate>"))
        #expect(xml.contains("<cbc:PaymentDueDate>2026-06-15</cbc:PaymentDueDate>"))
        let invoiceXML = try UBLInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(invoiceXML.contains("<cbc:DueDate>2026-06-15</cbc:DueDate>"))
        #expect(!invoiceXML.contains("<cbc:PaymentDueDate>"))
    }

    @Test("Credit note without IBAN still carries BT-9 via PaymentMeans (BR-CO-25)")
    func creditNoteWithoutIBANKeepsDueDate() throws {
        var doc = DemoData.sampleInvoice()
        doc.type = .creditNote
        doc.precedingInvoiceNumber = "INV-2026-0007"
        doc.paymentMeans.iban = ""
        doc.paymentTerms = ""
        let xml = try UBLInvoiceWriter().xml(for: doc)
        #expect(xml.contains("<cbc:PaymentDueDate>2026-06-15</cbc:PaymentDueDate>"))
        #expect(!xml.contains("<cac:PayeeFinancialAccount>"))
    }

    @Test("Discounted negative-quantity line reconciles via a line charge")
    func negativeQuantityLineDiscount() throws {
        var doc = DemoData.sampleInvoice()
        doc.lines = [
            LineItem(
                id: "l1", name: "Correction", quantity: -1, unitPrice: 100,
                discountPercent: 10, vatCategory: .standard, vatRatePercent: 25.5)
        ]
        let xml = try UBLInvoiceWriter().xml(for: doc)
        #expect(xml.contains("<cbc:ChargeIndicator>true</cbc:ChargeIndicator>"))
        #expect(xml.contains("<cbc:Amount currencyID=\"EUR\">10.00</cbc:Amount>"))
        #expect(xml.contains("<cbc:LineExtensionAmount currencyID=\"EUR\">-90.00</cbc:LineExtensionAmount>"))
    }

    @Test("Outside-scope (O) documents carry no VAT rate anywhere (BR-O-5/BR-O-10)")
    func outsideScopeOmitsRate() throws {
        var doc = DemoData.sampleInvoice()
        doc.lines = [
            LineItem(id: "l1", name: "Out of scope service", quantity: 1, unitPrice: 500, vatCategory: .outsideScope)
        ]
        let xml = try UBLInvoiceWriter().xml(for: doc)
        #expect(!xml.contains("<cbc:Percent>"))
        #expect(xml.contains("<cbc:ID>O</cbc:ID>"))
    }

    @Test("Output is well-formed XML")
    func wellFormed() throws {
        let xml = try UBLInvoiceWriter().xml(for: DemoData.sampleInvoice())
        let parser = XMLParser(data: Data(xml.utf8))
        #expect(parser.parse())
    }
}

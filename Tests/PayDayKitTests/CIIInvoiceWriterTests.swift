import Testing
import Foundation
@testable import PayDayKit

@Suite("CII / Factur-X writer")
struct CIIInvoiceWriterTests {
    @Test("EN 16931 profile and document header")
    func header() throws {
        let xml = try CIIInvoiceWriter(profile: .en16931).xml(for: DemoData.sampleInvoice())
        #expect(xml.contains("rsm:CrossIndustryInvoice"))
        #expect(xml.contains("urn:cen.eu:en16931:2017"))
        #expect(xml.contains("<ram:ID>INV-2026-0007</ram:ID>"))
        #expect(xml.contains("<ram:TypeCode>380</ram:TypeCode>"))
        #expect(xml.contains("format=\"102\">20260601"))
    }

    @Test("Monetary summation matches the engine")
    func summation() throws {
        let xml = try CIIInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(xml.contains("<ram:LineTotalAmount>5200.00</ram:LineTotalAmount>"))
        #expect(xml.contains("<ram:TaxBasisTotalAmount>5200.00</ram:TaxBasisTotalAmount>"))
        #expect(xml.contains("<ram:TaxTotalAmount currencyID=\"EUR\">1326.00</ram:TaxTotalAmount>"))
        #expect(xml.contains("<ram:GrandTotalAmount>6526.00</ram:GrandTotalAmount>"))
        #expect(xml.contains("<ram:DuePayableAmount>6526.00</ram:DuePayableAmount>"))
    }

    @Test("Seller VAT registration and party names")
    func parties() throws {
        let xml = try CIIInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(xml.contains("<ram:SellerTradeParty>"))
        #expect(xml.contains("<ram:Name>Aurora Studio Oy</ram:Name>"))
        #expect(xml.contains("<ram:ID schemeID=\"VA\">FI12345678</ram:ID>"))
        #expect(xml.contains("<ram:CountryID>FI</ram:CountryID>"))
    }

    @Test("Intra-community line emits category K, 0% and exemption reason")
    func intraCommunity() throws {
        let xml = try CIIInvoiceWriter().xml(for: DemoData.sampleIntraCommunityInvoice())
        #expect(xml.contains("<ram:CategoryCode>K</ram:CategoryCode>"))
        #expect(xml.contains("<ram:RateApplicablePercent>0.00</ram:RateApplicablePercent>"))
        #expect(xml.contains("<ram:ExemptionReason>Intra-Community supply</ram:ExemptionReason>"))
        #expect(xml.contains("<ram:TaxTotalAmount currencyID=\"EUR\">0.00</ram:TaxTotalAmount>"))
    }

    @Test("Estimates are never e-invoiceable")
    func estimateRejected() {
        var doc = DemoData.sampleInvoice()
        doc.type = .estimate
        #expect(throws: EInvoiceError.self) { try CIIInvoiceWriter().xml(for: doc) }
    }

    @Test("Carries business process, buyer reference, and seller contact")
    func peppolAndXRechnungTerms() throws {
        let xml = try CIIInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(xml.contains("<ram:BusinessProcessSpecifiedDocumentContextParameter>"))
        #expect(xml.contains("urn:fdc:peppol.eu:2017:poacc:billing:01:1.0"))
        #expect(xml.contains("<ram:BuyerReference>PO-SAIMAA-2026-04</ram:BuyerReference>"))
        #expect(xml.contains("<ram:DefinedTradeContact>"))
        #expect(xml.contains("<ram:PersonName>Marcus Ziadé</ram:PersonName>"))
    }

    @Test("Discounted line reconciles via a BG-27 line allowance (BT-131 = net price × qty − allowance)")
    func discountedLineCalculation() throws {
        // Demo line l2: 1 × 2400 with a 10% discount → net 2160.00, allowance 240.00.
        // The net price (BT-146) stays the full 2400.00 and the allowance closes
        // the gap, so the CII line-calculation rule holds exactly.
        let xml = try CIIInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(xml.contains("<ram:SpecifiedTradeAllowanceCharge>"))
        #expect(xml.contains("<udt:Indicator>false</udt:Indicator>"))
        #expect(xml.contains("<ram:ActualAmount>240.00</ram:ActualAmount>"))
        #expect(xml.contains("<ram:Reason>Discount</ram:Reason>"))
        #expect(xml.contains("<ram:ChargeAmount>2400.00</ram:ChargeAmount>"))
        #expect(xml.contains("<ram:LineTotalAmount>2160.00</ram:LineTotalAmount>"))
        // An undiscounted line carries no allowance noise.
        var noDiscount = DemoData.sampleInvoice()
        noDiscount.lines = [noDiscount.lines[0]]
        let plain = try CIIInvoiceWriter().xml(for: noDiscount)
        #expect(!plain.contains("<ram:SpecifiedTradeAllowanceCharge>"))
    }

    @Test("Payment means normalises the IBAN and carries the remittance reference (BT-83/BT-84)")
    func paymentMeansNormalised() throws {
        let xml = try CIIInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(xml.contains("<ram:PaymentReference>RF18 0007</ram:PaymentReference>"))
        #expect(xml.contains("<ram:IBANID>FI2112345600000785</ram:IBANID>"))
        #expect(!xml.contains("FI21 1234"))
    }

    @Test("Output is well-formed XML")
    func wellFormed() throws {
        let xml = try CIIInvoiceWriter().xml(for: DemoData.sampleInvoice())
        #expect(xml.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        let data = Data(xml.utf8)
        let parser = XMLParser(data: data)
        #expect(parser.parse())
    }
}

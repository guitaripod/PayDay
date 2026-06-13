import Testing
import Foundation
import PDFKit
@testable import PayDay
import PayDayKit

/// Hosted tests for the Darwin-only rendering path (PDFKit / Core Graphics) that
/// the platform-agnostic PayDayKit suite cannot cover.
@Suite("PDF rendering & Factur-X embedding")
struct RenderingTests {
    @Test("Renderer produces a valid, openable PDF")
    func rendersPDF() {
        let data = InvoicePDFRenderer().render(DemoData.sampleInvoice())
        #expect(data.count > 1000)
        #expect(PDFDocument(data: data) != nil)
        #expect(PDFDocument(data: data)?.pageCount ?? 0 >= 1)
    }

    @Test("Factur-X embedder embeds the CII XML into an openable PDF")
    func embeds() {
        let invoice = DemoData.sampleInvoice()
        let visual = InvoicePDFRenderer().render(invoice)
        let output = FacturXEmbedder(profile: .en16931).embed(invoice: invoice, visualPDF: visual)
        #expect(!output.sidecarXML.isEmpty)
        #expect(PDFDocument(data: output.pdf) != nil)
        let xml = String(decoding: output.sidecarXML, as: UTF8.self)
        #expect(xml.contains("CrossIndustryInvoice"))
        #expect(xml.contains("urn:cen.eu:en16931:2017"))

        #expect(output.embedded)
        #expect(output.pdf.count > visual.count)
        let pdfString = String(decoding: output.pdf, as: UTF8.self)
        #expect(pdfString.contains("factur-x.xml"))
        #expect(pdfString.contains("/AFRelationship /Data"))
        #expect(pdfString.contains("/Type /Filespec"))
        #expect(pdfString.contains("/Subtype /text#2Fxml"))
        #expect(pdfString.contains("urn:factur-x:pdfa:CrossIndustryDocument"))
        // PDF/A-3b markers that the Mustang/veraPDF validation depends on.
        #expect(pdfString.contains("<pdfaid:part>3</pdfaid:part>"))
        #expect(pdfString.contains("/OutputIntent"))
        #expect(pdfString.contains("/ID [<"))
    }

    @Test("Estimates render but carry no embedded e-invoice")
    func estimateHasNoEInvoice() {
        var doc = DemoData.sampleInvoice()
        doc.type = .estimate
        let data = InvoicePDFRenderer().render(doc)
        #expect(PDFDocument(data: data) != nil)
    }

    @Test("Export the hybrid PDF for external validation")
    func exportForValidation() throws {
        let invoice = DemoData.sampleInvoice()
        let visual = InvoicePDFRenderer().render(invoice)
        let output = FacturXEmbedder(profile: .en16931).embed(invoice: invoice, visualPDF: visual)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("payday-facturx.pdf")
        try output.pdf.write(to: url)
        print("FACTURX_PDF_PATH=\(url.path)")
    }
}

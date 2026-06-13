import Foundation
import CryptoKit
import PayDayKit

/// Turns a rendered visual PDF into a Factur-X / PDF-A-3 hybrid by appending a
/// classic incremental update that adds, to satisfy veraPDF's PDF/A-3b rules:
///   • the EN 16931 CII XML as an associated file (`AFRelationship /Data`,
///     name `factur-x.xml`) reachable via `/AF` and `/Names/EmbeddedFiles`;
///   • an sRGB ICC `OutputIntent` (PDF/A requires a declared output condition);
///   • PDF/A-3 identification XMP plus the Factur-X extension-schema description
///     (so the `fx:` properties are "defined"), and a `/Metadata` stream;
///   • a document trailer `/ID`.
///
/// The base PDF must itself be transparency-free (see `InvoicePDFRenderer`'s
/// opaque palette) for the result to validate. The standalone `factur-x.xml`
/// sidecar and the Peppol UBL are produced regardless, so e-invoicing never
/// depends on byte-perfect PDF/A.
final class FacturXEmbedder {
    static let attachmentName = "factur-x.xml"

    struct Output {
        let pdf: Data
        let embedded: Bool
        let sidecarXML: Data
    }

    private let profile: EInvoiceProfile

    init(profile: EInvoiceProfile = .en16931) {
        self.profile = profile
    }

    func embed(invoice: Invoice, visualPDF: Data) -> Output {
        let xml = (try? CIIInvoiceWriter(profile: profile).xml(for: invoice)) ?? ""
        let sidecar = Data(xml.utf8)
        guard !xml.isEmpty, let hybrid = appendIncrementalUpdate(to: visualPDF, ciiXML: sidecar, invoice: invoice) else {
            AppLogger.shared.warn("Factur-X embed fell back to sidecar XML", category: .einvoice)
            return Output(pdf: visualPDF, embedded: false, sidecarXML: sidecar)
        }
        AppLogger.shared.info("embedded Factur-X (\(profile.rawValue)) into PDF", category: .einvoice)
        return Output(pdf: hybrid, embedded: true, sidecarXML: sidecar)
    }

    // MARK: Incremental update

    private func appendIncrementalUpdate(to pdf: Data, ciiXML: Data, invoice: Invoice) -> Data? {
        guard var text = String(data: pdf, encoding: .isoLatin1),
              let prevStartxref = lastStartxref(in: text),
              let trailer = parseTrailer(in: text),
              let root = parseObject(number: trailer.rootNumber, in: text)
        else { return nil }

        if !text.hasSuffix("\n") { text += "\n" }
        var output = text
        var nextObject = trailer.size
        var xref: [(number: Int, offset: Int)] = []

        func byteLength(_ s: String) -> Int { s.data(using: .isoLatin1)?.count ?? s.utf8.count }
        func appendObject(_ number: Int, _ body: String) {
            xref.append((number, byteLength(output)))
            output += "\(number) 0 obj\n\(body)\nendobj\n"
        }

        let embeddedFileNumber = nextObject; nextObject += 1
        let filespecNumber = nextObject; nextObject += 1
        let metadataNumber = nextObject; nextObject += 1
        let iccNumber: Int? = iccProfileData() != nil ? { let n = nextObject; nextObject += 1; return n }() : nil

        let stamp = pdfDateString()
        let xmlString = String(data: ciiXML, encoding: .isoLatin1) ?? ""
        appendObject(embeddedFileNumber, """
        << /Type /EmbeddedFile /Subtype /text#2Fxml /Params << /ModDate (\(stamp)) /Size \(ciiXML.count) >> /Length \(ciiXML.count) >>
        stream
        \(xmlString)
        endstream
        """)

        appendObject(filespecNumber, """
        << /Type /Filespec /F (\(Self.attachmentName)) /UF (\(Self.attachmentName)) /AFRelationship /Data /Desc (Factur-X EN 16931 invoice) /EF << /F \(embeddedFileNumber) 0 R /UF \(embeddedFileNumber) 0 R >> >>
        """)

        let xmp = facturXMP(invoice: invoice)
        let xmpData = Data(xmp.utf8)
        appendObject(metadataNumber, """
        << /Type /Metadata /Subtype /XML /Length \(xmpData.count) >>
        stream
        \(String(data: xmpData, encoding: .isoLatin1) ?? xmp)
        endstream
        """)

        if let iccNumber, let icc = iccProfileData(), let iccString = String(data: icc, encoding: .isoLatin1) {
            appendObject(iccNumber, """
            << /N 3 /Length \(icc.count) >>
            stream
            \(iccString)
            endstream
            """)
        }

        var additions = "/AF [\(filespecNumber) 0 R] "
            + "/Names << /EmbeddedFiles << /Names [(\(Self.attachmentName)) \(filespecNumber) 0 R] >> >> "
            + "/Metadata \(metadataNumber) 0 R"
        if let iccNumber {
            additions += " /OutputIntents [ << /Type /OutputIntent /S /GTS_PDFA1 "
                + "/OutputConditionIdentifier (sRGB IEC61966-2.1) /Info (sRGB IEC61966-2.1) "
                + "/DestOutputProfile \(iccNumber) 0 R >> ]"
        }
        guard let mergedRoot = mergeCatalog(root.body, additions: additions) else { return nil }
        appendObject(trailer.rootNumber, mergedRoot)

        let xrefOffset = byteLength(output)
        let docID = documentID(invoice: invoice, size: pdf.count)
        output += buildXrefSection(
            entries: xref, size: nextObject, rootNumber: trailer.rootNumber,
            prev: prevStartxref, xrefOffset: xrefOffset, id: docID)

        return output.data(using: .isoLatin1)
    }

    // MARK: PDF parsing helpers

    private func lastStartxref(in text: String) -> Int? {
        guard let range = text.range(of: "startxref", options: .backwards) else { return nil }
        let tail = text[range.upperBound...]
        let digits = tail.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    private struct Trailer { let rootNumber: Int; let size: Int }

    private func parseTrailer(in text: String) -> Trailer? {
        guard let trailerRange = text.range(of: "trailer", options: .backwards) else { return nil }
        let tail = String(text[trailerRange.upperBound...])
        guard let root = firstMatch(in: tail, pattern: #"/Root\s+(\d+)\s+\d+\s+R"#),
              let size = firstMatch(in: tail, pattern: #"/Size\s+(\d+)"#)
        else { return nil }
        return Trailer(rootNumber: root, size: size)
    }

    private struct ParsedObject { let body: String }

    private func parseObject(number: Int, in text: String) -> ParsedObject? {
        guard let startRange = text.range(of: "\(number) 0 obj") else { return nil }
        let after = text[startRange.upperBound...]
        guard let endRange = after.range(of: "endobj") else { return nil }
        return ParsedObject(body: String(after[after.startIndex..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Merge `additions` into a catalog dictionary body by splicing before its
    /// final `>>`. Returns nil if the body is not a recognisable dictionary.
    private func mergeCatalog(_ body: String, additions: String) -> String? {
        guard let close = body.range(of: ">>", options: .backwards) else { return nil }
        var merged = String(body[body.startIndex..<close.lowerBound])
        if !merged.hasSuffix(" ") { merged += " " }
        merged += additions + " >>"
        return merged
    }

    private func buildXrefSection(entries: [(number: Int, offset: Int)], size: Int, rootNumber: Int, prev: Int, xrefOffset: Int, id: String) -> String {
        var section = "xref\n"
        for entry in entries.sorted(by: { $0.number < $1.number }) {
            section += "\(entry.number) 1\n"
            section += String(format: "%010d 00000 n \n", entry.offset)
        }
        section += "trailer\n<< /Size \(size) /Root \(rootNumber) 0 R /Prev \(prev) /ID [<\(id)> <\(id)>] >>\n"
        section += "startxref\n\(xrefOffset)\n%%EOF\n"
        return section
    }

    private func firstMatch(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[range])
    }

    private func iccProfileData() -> Data? {
        guard let url = Bundle.main.url(forResource: "sRGB", withExtension: "icc") else { return nil }
        return try? Data(contentsOf: url)
    }

    private func documentID(invoice: Invoice, size: Int) -> String {
        let digest = SHA256.hash(data: Data("\(invoice.id)|\(invoice.number)|\(size)".utf8))
        return digest.prefix(16).map { String(format: "%02X", $0) }.joined()
    }

    private func pdfDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return "D:\(formatter.string(from: Date()))Z"
    }

    /// XMP with the PDF/A-3 identification schema, the Factur-X extension-schema
    /// description (so `fx:` properties validate), and dc/xmp basics that mirror
    /// the document Info dictionary.
    private func facturXMP(invoice: Invoice) -> String {
        let title = "\(invoice.type.displayName) \(invoice.number)"
        return """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/">
           <pdfaid:part>3</pdfaid:part>
           <pdfaid:conformance>B</pdfaid:conformance>
          </rdf:Description>
          <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
           <dc:title><rdf:Alt><rdf:li xml:lang="x-default">\(XMLBuilder.escapeText(title))</rdf:li></rdf:Alt></dc:title>
          </rdf:Description>
          <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
           <xmp:CreatorTool>Pay Day</xmp:CreatorTool>
          </rdf:Description>
          <rdf:Description rdf:about="" xmlns:fx="urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#">
           <fx:DocumentType>INVOICE</fx:DocumentType>
           <fx:DocumentFileName>\(Self.attachmentName)</fx:DocumentFileName>
           <fx:Version>1.0</fx:Version>
           <fx:ConformanceLevel>\(profile.xmpConformanceLevel)</fx:ConformanceLevel>
          </rdf:Description>
          <rdf:Description rdf:about=""
           xmlns:pdfaExtension="http://www.aiim.org/pdfa/ns/extension/"
           xmlns:pdfaSchema="http://www.aiim.org/pdfa/ns/schema#"
           xmlns:pdfaProperty="http://www.aiim.org/pdfa/ns/property#">
           <pdfaExtension:schemas>
            <rdf:Bag>
             <rdf:li rdf:parseType="Resource">
              <pdfaSchema:schema>Factur-X PDFA Extension Schema</pdfaSchema:schema>
              <pdfaSchema:namespaceURI>urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#</pdfaSchema:namespaceURI>
              <pdfaSchema:prefix>fx</pdfaSchema:prefix>
              <pdfaSchema:property>
               <rdf:Seq>
                <rdf:li rdf:parseType="Resource">
                 <pdfaProperty:name>DocumentFileName</pdfaProperty:name>
                 <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                 <pdfaProperty:category>external</pdfaProperty:category>
                 <pdfaProperty:description>name of the embedded XML invoice file</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                 <pdfaProperty:name>DocumentType</pdfaProperty:name>
                 <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                 <pdfaProperty:category>external</pdfaProperty:category>
                 <pdfaProperty:description>INVOICE</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                 <pdfaProperty:name>Version</pdfaProperty:name>
                 <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                 <pdfaProperty:category>external</pdfaProperty:category>
                 <pdfaProperty:description>version of the Factur-X standard</pdfaProperty:description>
                </rdf:li>
                <rdf:li rdf:parseType="Resource">
                 <pdfaProperty:name>ConformanceLevel</pdfaProperty:name>
                 <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                 <pdfaProperty:category>external</pdfaProperty:category>
                 <pdfaProperty:description>conformance level of the Factur-X data</pdfaProperty:description>
                </rdf:li>
               </rdf:Seq>
              </pdfaSchema:property>
             </rdf:li>
            </rdf:Bag>
           </pdfaExtension:schemas>
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
    }
}

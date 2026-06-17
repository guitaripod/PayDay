import UIKit
import PayDayKit

/// Renders an invoice/estimate to a clean, professional A4 PDF. The same
/// `Invoice` value drives this visual document and the EN 16931 XML, so a human
/// and a machine can never be shown different numbers.
final class InvoicePDFRenderer {
    struct Style {
        var accent: UIColor = DesignSystem.Color.accent
        var logo: UIImage?
        var locale: Locale = .current
    }

    private let pageSize = CGSize(width: 595.2, height: 841.8) // A4 @ 72dpi
    private let margin: CGFloat = 48
    private let style: Style

    /// A fixed, fully-opaque print palette. PDF/A-3 forbids transparency
    /// (alpha < 1 trips veraPDF's ExtGState `ca`/`CA` rule), and a PDF should not
    /// inherit the device's dark-mode semantic colours — so we never use the
    /// system label colours (which carry alpha) in the rendered document.
    private enum Ink {
        static let primary = UIColor(white: 0, alpha: 1)
        static let secondary = UIColor(white: 0.36, alpha: 1)
        static let tertiary = UIColor(white: 0.55, alpha: 1)
        static let hairline = UIColor(white: 0.80, alpha: 1)
    }

    init(style: Style = Style()) {
        self.style = style
    }

    func render(_ invoice: Invoice) -> Data {
        let totals = invoice.totals()
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(invoice.type.displayName) \(invoice.number)",
            kCGPDFContextAuthor as String: invoice.seller.legalName,
            kCGPDFContextCreator as String: "Pay Day",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            var y = margin
            y = drawHeader(invoice, top: y)
            y = drawParties(invoice, top: y + 24)
            y = drawMeta(invoice, top: y + 16)
            y = drawLineTable(invoice, totals: totals, top: y + 20, context: ctx)
            y = drawTotals(totals, top: y + 12)
            y = drawVATBreakdown(totals, top: y + 16)
            y = drawPayment(invoice, top: y + 18)
            drawFooter(invoice)
        }
    }

    // MARK: Sections

    private func drawHeader(_ invoice: Invoice, top: CGFloat) -> CGFloat {
        let contentWidth = pageSize.width - margin * 2
        var y = top
        if let logo = style.logo {
            let maxLogo = CGSize(width: 140, height: 64)
            let size = aspectFit(logo.size, into: maxLogo)
            logo.draw(in: CGRect(x: margin, y: y, width: size.width, height: size.height))
        } else {
            draw(invoice.seller.displayName, at: CGPoint(x: margin, y: y),
                 font: .systemFont(ofSize: 20, weight: .bold), color: style.accent)
        }
        let title = invoice.type.displayName.uppercased()
        let titleAttr = attributed(title, font: .systemFont(ofSize: 26, weight: .heavy), color: Ink.primary)
        let titleSize = titleAttr.size()
        titleAttr.draw(at: CGPoint(x: margin + contentWidth - titleSize.width, y: y))
        y += max(64, titleSize.height)

        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y + 6))
        line.addLine(to: CGPoint(x: margin + contentWidth, y: y + 6))
        style.accent.setStroke()
        line.lineWidth = 2
        line.stroke()
        return y + 8
    }

    private func drawParties(_ invoice: Invoice, top: CGFloat) -> CGFloat {
        let columnWidth = (pageSize.width - margin * 2) / 2 - 12
        let sellerHeight = drawPartyBlock("From", party: invoice.seller, x: margin, y: top, width: columnWidth)
        let buyerHeight = drawPartyBlock("Bill to", party: invoice.buyer, x: margin + columnWidth + 24, y: top, width: columnWidth)
        return top + max(sellerHeight, buyerHeight)
    }

    private func drawPartyBlock(_ caption: String, party: Party, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        var cursor = y
        draw(caption.uppercased(), at: CGPoint(x: x, y: cursor),
             font: .systemFont(ofSize: 10, weight: .bold), color: Ink.secondary)
        cursor += 16
        cursor += drawWrapped(party.legalName, x: x, y: cursor, width: width,
                              font: .systemFont(ofSize: 14, weight: .semibold), color: Ink.primary)
        let lines = [party.address.singleLine, party.email, party.hasVATID ? "VAT \(party.vatID)" : ""]
            .filter { !$0.isEmpty }
        for line in lines {
            cursor += drawWrapped(line, x: x, y: cursor, width: width,
                                  font: .systemFont(ofSize: 11), color: Ink.secondary)
        }
        return cursor - y
    }

    private func drawMeta(_ invoice: Invoice, top: CGFloat) -> CGFloat {
        let items: [(String, String)] = [
            ("\(invoice.type.displayName) no.", invoice.number),
            ("Issued", Format.date(invoice.issueDate, locale: style.locale)),
            ("Due", Format.date(invoice.dueDate, locale: style.locale)),
        ]
        var x = margin
        let columnWidth = (pageSize.width - margin * 2) / CGFloat(items.count)
        for (caption, value) in items {
            draw(caption.uppercased(), at: CGPoint(x: x, y: top),
                 font: .systemFont(ofSize: 9, weight: .bold), color: Ink.secondary)
            draw(value, at: CGPoint(x: x, y: top + 13),
                 font: .systemFont(ofSize: 13, weight: .semibold), color: Ink.primary)
            x += columnWidth
        }
        return top + 32
    }

    private func drawLineTable(_ invoice: Invoice, totals: ComputedTotals, top: CGFloat, context: UIGraphicsPDFRendererContext) -> CGFloat {
        let contentWidth = pageSize.width - margin * 2
        let cols: [CGFloat] = [margin, margin + contentWidth * 0.48, margin + contentWidth * 0.62, margin + contentWidth * 0.78]
        var y = top

        drawTableHeader(at: y, cols: cols, contentWidth: contentWidth)
        y += 22

        for (index, line) in invoice.lines.enumerated() {
            if y > pageSize.height - 200 {
                context.beginPage()
                y = margin
                drawTableHeader(at: y, cols: cols, contentWidth: contentWidth)
                y += 22
            }
            let net = totals.lineNets[index]
            let nameHeight = drawWrapped(line.name, x: cols[0], y: y, width: cols[1] - cols[0] - 8,
                                         font: .systemFont(ofSize: 12, weight: .medium), color: Ink.primary)
            var rowBottom = y + nameHeight
            if !line.details.isEmpty {
                rowBottom += drawWrapped(line.details, x: cols[0], y: rowBottom, width: cols[1] - cols[0] - 8,
                                         font: .systemFont(ofSize: 10), color: Ink.secondary)
            }
            let qty = "\(decimalDisplay(line.quantity)) \(line.unit.label)"
            drawRight(qty, rightEdge: cols[2] - 8, y: y, font: .systemFont(ofSize: 11), color: Ink.secondary)
            drawRight(decimalDisplay(line.effectiveRate) + "%", rightEdge: cols[3] - 8, y: y,
                      font: .systemFont(ofSize: 11), color: Ink.secondary)
            drawRight(Format.money(net, locale: style.locale), rightEdge: margin + contentWidth, y: y,
                      font: .systemFont(ofSize: 12, weight: .semibold), color: Ink.primary)
            y = rowBottom + 10
            drawSeparator(at: y - 4, width: contentWidth)
        }
        return y
    }

    private func drawTableHeader(at y: CGFloat, cols: [CGFloat], contentWidth: CGFloat) {
        let font = UIFont.systemFont(ofSize: 9, weight: .bold)
        draw("DESCRIPTION", at: CGPoint(x: cols[0], y: y), font: font, color: Ink.secondary)
        drawRight("QTY", rightEdge: cols[2] - 8, y: y, font: font, color: Ink.secondary)
        drawRight("VAT", rightEdge: cols[3] - 8, y: y, font: font, color: Ink.secondary)
        drawRight("AMOUNT", rightEdge: margin + contentWidth, y: y, font: font, color: Ink.secondary)
        drawSeparator(at: y + 16, width: contentWidth)
    }

    private func drawTotals(_ totals: ComputedTotals, top: CGFloat) -> CGFloat {
        let contentWidth = pageSize.width - margin * 2
        let labelX = margin + contentWidth * 0.55
        var y = top
        let s = totals.summary
        func row(_ label: String, _ money: Money, bold: Bool = false) {
            draw(label, at: CGPoint(x: labelX, y: y),
                 font: .systemFont(ofSize: bold ? 14 : 12, weight: bold ? .bold : .regular),
                 color: bold ? .label : Ink.secondary)
            drawRight(Format.money(money, locale: style.locale), rightEdge: margin + contentWidth, y: y,
                      font: .monospacedDigitSystemFont(ofSize: bold ? 15 : 12, weight: bold ? .bold : .medium),
                      color: bold ? .label : Ink.primary)
            y += bold ? 24 : 19
        }
        row("Subtotal", s.taxExclusiveTotal)
        if !s.allowanceTotal.isZero { row("Discounts", -s.allowanceTotal) }
        if !s.chargeTotal.isZero { row("Charges", s.chargeTotal) }
        row("VAT", s.taxTotal)
        drawSeparator(at: y - 2, width: contentWidth * 0.45, x: labelX)
        y += 6
        row("Total due", s.payableAmount, bold: true)
        return y
    }

    private func drawVATBreakdown(_ totals: ComputedTotals, top: CGFloat) -> CGFloat {
        guard totals.breakdowns.count > 1 || totals.breakdowns.contains(where: { $0.category != .standard }) else { return top }
        var y = top
        draw("VAT BREAKDOWN", at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 9, weight: .bold), color: Ink.secondary)
        y += 15
        for b in totals.breakdowns {
            let rate = "\(decimalDisplay(b.ratePercent))%"
            let label = "\(b.category.displayName) \(rate) on \(Format.money(b.taxableBase, locale: style.locale))"
            draw(label, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 10), color: Ink.secondary)
            drawRight(Format.money(b.taxAmount, locale: style.locale), rightEdge: margin + 240, y: y,
                      font: .systemFont(ofSize: 10, weight: .medium), color: Ink.primary)
            y += 14
            if b.category.requiresExemptionReason && !b.exemptionReason.isEmpty {
                y += drawWrapped(b.exemptionReason, x: margin, y: y, width: 360,
                                 font: .italicSystemFont(ofSize: 9), color: Ink.tertiary)
            }
        }
        return y
    }

    private func drawPayment(_ invoice: Invoice, top: CGFloat) -> CGFloat {
        var y = top
        let means = invoice.paymentMeans
        if !means.iban.isEmpty {
            draw("PAYMENT", at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 9, weight: .bold), color: Ink.secondary)
            y += 15
            let lines = [
                "IBAN  \(means.iban)",
                means.bic.isEmpty ? "" : "BIC  \(means.bic)",
                means.remittanceReference.isEmpty ? "" : "Reference  \(means.remittanceReference)",
            ].filter { !$0.isEmpty }
            for line in lines {
                draw(line, at: CGPoint(x: margin, y: y), font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: Ink.primary)
                y += 16
            }
        }
        if !invoice.paymentTerms.isEmpty {
            y += drawWrapped(invoice.paymentTerms, x: margin, y: y + 4, width: pageSize.width - margin * 2,
                             font: .systemFont(ofSize: 10), color: Ink.secondary)
        }
        if !invoice.note.isEmpty {
            y += drawWrapped(invoice.note, x: margin, y: y + 4, width: pageSize.width - margin * 2,
                             font: .italicSystemFont(ofSize: 10), color: Ink.secondary)
        }
        return y
    }

    private func drawFooter(_ invoice: Invoice) {
        let isCompliant = invoice.type.isEInvoiceable && InvoiceValidator.isCompliant(invoice)
        let text = isCompliant
            ? "Generated by Pay Day · EN 16931-valid e-invoice available"
            : "Generated by Pay Day"
        let attr = attributed(text, font: .systemFont(ofSize: 8), color: Ink.tertiary)
        attr.draw(at: CGPoint(x: margin, y: pageSize.height - margin + 8))
    }

    // MARK: Drawing helpers

    private func attributed(_ text: String, font: UIFont, color: UIColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    private func draw(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        attributed(text, font: font, color: color).draw(at: point)
    }

    private func drawRight(_ text: String, rightEdge: CGFloat, y: CGFloat, font: UIFont, color: UIColor) {
        let attr = attributed(text, font: font, color: color)
        attr.draw(at: CGPoint(x: rightEdge - attr.size().width, y: y))
    }

    @discardableResult
    private func drawWrapped(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, font: UIFont, color: UIColor) -> CGFloat {
        let attr = attributed(text, font: font, color: color)
        let rect = attr.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        attr.draw(with: CGRect(x: x, y: y, width: width, height: ceil(rect.height)),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return ceil(rect.height) + 2
    }

    private func drawSeparator(at y: CGFloat, width: CGFloat, x: CGFloat? = nil) {
        let path = UIBezierPath()
        let startX = x ?? margin
        path.move(to: CGPoint(x: startX, y: y))
        path.addLine(to: CGPoint(x: startX + width, y: y))
        Ink.hairline.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }

    private func aspectFit(_ size: CGSize, into bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func decimalDisplay(_ value: Decimal) -> String {
        let number = value as NSDecimalNumber
        if number == number.rounding(accordingToBehavior: nil) {
            return String(number.intValue)
        }
        return number.stringValue
    }
}

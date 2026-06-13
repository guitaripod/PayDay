import Foundation
import PayDayKit
import AICreditsCore

/// AI actions powered by mako (metered as credits). Each genuinely changes the
/// outcome: a photo of a quote/receipt becomes line items; plain language
/// becomes line items; an overdue invoice becomes a tactful reminder email.
final class InvoiceAIService: Sendable {
    private let client: AICreditsClient

    init(client: AICreditsClient = AICreditsManager.shared.client) {
        self.client = client
    }

    struct DraftedLine: Sendable {
        let name: String
        let details: String
        let quantity: Decimal
        let unitPrice: Decimal
    }

    /// Turn a base64 image (receipt / quote / handwritten note) into line items.
    func lineItems(fromImageBase64 image: String, currency: Currency) async throws -> [DraftedLine] {
        let prompt = """
        Extract billable line items from this image of a quote, receipt, or notes. \
        Reply with JSON only: {"lines":[{"name","details","quantity","unit_price"}]}. \
        Amounts are in \(currency.code); unit_price is the net price per unit as a number.
        """
        let request = CapabilityRequest.chat(
            messages: [ChatTurn(role: "user", content: prompt)],
            images: [image],
            responseJSON: true)
        let result = try await client.run(request)
        return Self.parseLines(result.raw)
    }

    /// Turn a plain-language description into line items.
    func lineItems(fromText text: String, currency: Currency) async throws -> [DraftedLine] {
        let prompt = """
        Turn this freelancer's description into billable line items. \
        Reply with JSON only: {"lines":[{"name","details","quantity","unit_price"}]}. \
        Amounts are in \(currency.code); unit_price is the net price per unit as a number.

        Description: \(text)
        """
        let request = CapabilityRequest.chat(
            messages: [ChatTurn(role: "user", content: prompt)],
            responseJSON: true)
        let result = try await client.run(request)
        return Self.parseLines(result.raw)
    }

    /// Draft a payment-reminder email for an (over)due invoice.
    func paymentReminder(for invoice: Invoice, tone: String) async throws -> String {
        let total = Format.money(invoice.totals().summary.payableAmount)
        let prompt = """
        Write a \(tone) payment-reminder email to \(invoice.buyer.displayName) for invoice \
        \(invoice.number), amount \(total), due \(invoice.dueDate.iso8601). \
        Keep it under 120 words, professional, no placeholders. Plain text only.
        """
        let request = CapabilityRequest.chat(messages: [ChatTurn(role: "user", content: prompt)])
        let result = try await client.run(request)
        return Self.parseMessageContent(result.raw) ?? ""
    }

    // MARK: Response parsing (mako proxies an OpenAI-shaped chat completion)

    private struct ChatCompletion: Decodable {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
        let choices: [Choice]
    }

    private struct LinesPayload: Decodable {
        struct Line: Decodable {
            let name: String
            let details: String?
            let quantity: Double?
            let unit_price: Double?
        }
        let lines: [Line]
    }

    private static func parseMessageContent(_ data: Data) -> String? {
        (try? JSONDecoder().decode(ChatCompletion.self, from: data))?.choices.first?.message.content
    }

    private static func parseLines(_ data: Data) -> [DraftedLine] {
        guard let content = parseMessageContent(data),
              let payload = try? JSONDecoder().decode(LinesPayload.self, from: Data(content.utf8))
        else { return [] }
        return payload.lines.map {
            DraftedLine(
                name: $0.name,
                details: $0.details ?? "",
                quantity: sanitizedDecimal($0.quantity, default: 1),
                unitPrice: sanitizedDecimal($0.unit_price, default: 0))
        }
    }

    /// LLM-decoded numbers are untrusted: a non-finite or absurd-magnitude value
    /// would poison `Money(rounding:)` into garbage minor units that round-trip
    /// into the PDF and EN 16931 XML. Clamp to a finite, sane range at the boundary.
    private static func sanitizedDecimal(_ value: Double?, default fallback: Decimal) -> Decimal {
        guard let value, value.isFinite else { return fallback }
        let bounded = min(max(value, -1_000_000_000), 1_000_000_000)
        return Decimal(bounded)
    }
}

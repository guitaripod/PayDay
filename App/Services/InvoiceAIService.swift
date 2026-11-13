import Foundation
import PayDayCore
import AICreditsCore
import MidgarCore

/// AI actions powered by mako (metered as credits). Each genuinely changes the
/// outcome: a photo of a quote/receipt becomes line items; plain language
/// becomes line items; an overdue invoice becomes a reminder email in the tone asked for.
final class InvoiceAIService: Sendable {
    private let client: AICreditsClient
    private static let draftingModel = "claude-haiku-5-5"

    /// The English name of the language the app runs in ("Swedish", "Norwegian Bokmål"), which drafted text is
    /// written in.
    static var writingLanguage: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: "en").localizedString(forIdentifier: code) ?? "English"
    }

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
        Amounts are in \(currency.code); unit_price is the net price per unit as a number. \
        Write name and details in \(Self.writingLanguage).
        """
        let request = CapabilityRequest.chat(
            messages: [ChatTurn(role: "user", content: prompt)],
            images: [image],
            responseJSON: true,
            model: Self.draftingModel)
        let result = try await client.run(request)
        return Self.parseLines(result.raw)
    }

    /// Turn a plain-language description into line items.
    func lineItems(fromText text: String, currency: Currency) async throws -> [DraftedLine] {
        let prompt = """
        Turn this freelancer's description into billable line items. \
        Reply with JSON only: {"lines":[{"name","details","quantity","unit_price"}]}. \
        Amounts are in \(currency.code); unit_price is the net price per unit as a number. \
        Write name and details in \(Self.writingLanguage).

        Description: \(text)
        """
        let request = CapabilityRequest.chat(
            messages: [ChatTurn(role: "user", content: prompt)],
            responseJSON: true,
            model: Self.draftingModel)
        let result = try await client.run(request)
        return Self.parseLines(result.raw)
    }

    /// Why a reminder request came back without a draft a person should send.
    enum ReminderFailure: Error {
        case unusable
    }

    /// Drafts a payment reminder for an overdue invoice through mako's reminder alias, which holds the instructions.
    /// Only the client's name, the invoice number, the amount and the due date are sent. A reply that misstates one
    /// of them or adds a figure of its own is thrown away and asked for once more, which the service does not charge.
    func reminder(for invoice: Invoice, tone: ReminderTone) async throws -> ReminderDraft {
        let facts = ReminderFacts(
            client: invoice.buyer.displayName,
            invoiceNumber: invoice.number,
            amount: Format.money(invoice.totals().summary.payableAmount),
            dueDate: Format.date(invoice.dueDate))
        let first = UUID().uuidString
        if let draft = try await askForReminder(facts, tone: tone, key: first, retryOf: nil, signature: invoice.seller.displayName) {
            return draft
        }
        MidgarLog.notice("AI reminder was not usable, asking once more", category: .credits)
        if let draft = try await askForReminder(facts, tone: tone, key: UUID().uuidString, retryOf: first, signature: invoice.seller.displayName) {
            return draft
        }
        throw ReminderFailure.unusable
    }

    private func askForReminder(_ facts: ReminderFacts, tone: ReminderTone, key: String, retryOf: String?, signature: String) async throws -> ReminderDraft? {
        var parameters: [String: JSONValue] = [
            "alias": .string(PaymentReminder.alias),
            "input": .string(PaymentReminder.input(facts, tone: tone)),
            "language": .string(Self.writingLanguage),
            "idempotency_key": .string(key),
        ]
        if let retryOf { parameters["retry_of"] = .string(retryOf) }
        let result = try await client.run(CapabilityRequest(capability: .chat, parameters: parameters))
        guard let content = Self.aliasContent(result.raw) else { return nil }
        return PaymentReminder.draft(from: content, facts: facts, signature: signature)
    }

    /// The `content` of an alias reply, which is the model's JSON as a string.
    private static func aliasContent(_ data: Data) -> String? {
        struct AliasReply: Decodable {
            let content: String
        }
        return (try? JSONDecoder().decode(AliasReply.self, from: data))?.content
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
        if let decoded = try? JSONDecoder().decode(ChatCompletion.self, from: data) {
            return decoded.choices.first?.message.content
        }
        guard let envelope = extractJSONObject(from: String(decoding: data, as: UTF8.self)),
              let decoded = try? JSONDecoder().decode(ChatCompletion.self, from: Data(envelope.utf8))
        else { return nil }
        return decoded.choices.first?.message.content
    }

    private static func parseLines(_ data: Data) -> [DraftedLine] {
        guard let content = parseMessageContent(data) else { return [] }
        guard let payload = decodeLines(content) else {
            MidgarLog.error("AI line-item parse failed: \(content.count) characters, content withheld", category: .credits)
            return []
        }
        return payload.lines.map {
            DraftedLine(
                name: $0.name,
                details: $0.details ?? "",
                quantity: sanitizedDecimal($0.quantity, default: 1),
                unitPrice: sanitizedDecimal($0.unit_price, default: 0))
        }
    }

    private static func decodeLines(_ content: String) -> LinesPayload? {
        if let payload = try? JSONDecoder().decode(LinesPayload.self, from: Data(content.utf8)) {
            return payload
        }
        guard let json = extractJSONObject(from: content) else { return nil }
        return try? JSONDecoder().decode(LinesPayload.self, from: Data(json.utf8))
    }

    /// Models sometimes wrap JSON in markdown code fences or surround it with
    /// prose; isolate the first balanced top-level `{...}` (or bare `[...]`) so a
    /// usable result is never silently dropped over cosmetic framing.
    private static func extractJSONObject(from text: String) -> String? {
        let stripped = stripCodeFences(text)
        return firstBalancedJSON(in: stripped, open: "{", close: "}")
            ?? firstBalancedJSON(in: stripped, open: "[", close: "]")
    }

    private static func stripCodeFences(_ text: String) -> Substring {
        guard let fenceStart = text.range(of: "```") else { return text[...] }
        let afterOpen = text[fenceStart.upperBound...]
        let body = afterOpen.first == "\n"
            ? afterOpen.dropFirst()
            : afterOpen.drop(while: { $0 != "\n" }).dropFirst()
        guard let fenceEnd = body.range(of: "```") else { return body }
        return body[..<fenceEnd.lowerBound]
    }

    private static func firstBalancedJSON(in text: Substring, open: Character, close: Character) -> String? {
        guard let start = text.firstIndex(of: open) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == open {
                    depth += 1
                } else if character == close {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// LLM-decoded numbers are untrusted: a non-finite or absurd-magnitude value
    /// would poison `Money(rounding:)` into garbage minor units that round-trip
    /// into the PDF and EN 16931 XML. Clamp to a finite, sane range at the boundary.
    private static func sanitizedDecimal(_ value: Double?, default fallback: Decimal) -> Decimal {
        guard let value, value.isFinite else { return fallback }
        let bounded = min(max(value, -1_000_000_000), 1_000_000_000)
        return Decimal(string: String(format: "%.6f", bounded)) ?? fallback
    }
}

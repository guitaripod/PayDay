import Foundation

/// How firmly a payment reminder is worded.
public enum ReminderTone: String, CaseIterable, Sendable {
    case friendly
    case firm
    case final
}

/// What a reminder states about an overdue invoice, each written exactly as the reader should see it. These four are
/// all that leaves the device to have a reminder drafted.
public struct ReminderFacts: Equatable, Sendable {
    public let client: String
    public let invoiceNumber: String
    public let amount: String
    public let dueDate: String

    public init(client: String, invoiceNumber: String, amount: String, dueDate: String) {
        self.client = Self.oneLine(client)
        self.invoiceNumber = Self.oneLine(invoiceNumber)
        self.amount = Self.oneLine(amount)
        self.dueDate = Self.oneLine(dueDate)
    }

    /// A value on one line with plain spaces, so it cannot pose as another line of the request and compares equal
    /// however a formatter or a model spaced it.
    static func oneLine(_ text: String) -> String {
        let spaced = text.unicodeScalars.map { scalar -> Character in
            CharacterSet.whitespacesAndNewlines.contains(scalar) ? " " : Character(scalar)
        }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }
}

/// A drafted reminder that passed every check: ready to send as it is.
public struct ReminderDraft: Equatable, Sendable {
    public let subject: String
    public let body: String
}

/// The rules of a drafted payment reminder: what is asked of the service, and what a reply must hold before a
/// person sees it. A reminder states the invoice's own number, amount and due date and no other figure, so a model
/// can never add a fee, interest or a deadline of its own.
public enum PaymentReminder {
    public static let alias = "reminder.draft.v1"
    static let longestSubject = 140
    static let shortestBody = 40
    static let longestBody = 1_600

    /// The message the reminder alias reads: the tone and the four facts, a line each.
    public static func input(_ facts: ReminderFacts, tone: ReminderTone) -> String {
        """
        Tone: \(tone.rawValue)
        Client: \(facts.client)
        Invoice: \(facts.invoiceNumber)
        Amount: \(facts.amount)
        Due: \(facts.dueDate)
        """
    }

    /// The draft of a reply, or nil when the reply is not one a person should send: it must name the invoice, state
    /// the amount and the due date as given, hold no other figure and no percentage, and leave no placeholder to fill.
    /// `signature` is added on its own line under the closing, when there is one.
    public static func draft(from reply: String, facts: ReminderFacts, signature: String = "") -> ReminderDraft? {
        struct Wire: Decodable {
            let subject: String
            let body: String
        }
        guard let data = reply.data(using: .utf8), let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        let subject = ReminderFacts.oneLine(wire.subject)
        let body = paragraphs(wire.body)
        guard !subject.isEmpty, subject.count <= longestSubject, (shortestBody...longestBody).contains(body.count) else { return nil }
        let spoken = ReminderFacts.oneLine(subject + " " + body)
        guard spoken.contains(facts.invoiceNumber), spoken.contains(facts.amount), spoken.contains(facts.dueDate) else { return nil }
        guard !addsAnything(to: spoken, beyond: facts) else { return nil }
        let signed = ReminderFacts.oneLine(signature)
        return ReminderDraft(subject: subject, body: signed.isEmpty ? body : body + "\n" + signed)
    }

    /// Whether the text, once the facts it was given are taken out, still holds a figure, a percentage or a
    /// placeholder left to fill in.
    static func addsAnything(to text: String, beyond facts: ReminderFacts) -> Bool {
        var rest = text
        for known in [facts.amount, facts.dueDate, facts.invoiceNumber, facts.client].sorted(by: { $0.count > $1.count }) where !known.isEmpty {
            rest = rest.replacingOccurrences(of: known, with: " ")
        }
        return rest.contains { $0.isNumber || "[]{}<>%".contains($0) }
    }

    /// The body with each paragraph on plain spaces and one blank line between paragraphs.
    static func paragraphs(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map(ReminderFacts.oneLine)
            .reduce(into: [String]()) { lines, line in
                if line.isEmpty, lines.last?.isEmpty ?? true { return }
                lines.append(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

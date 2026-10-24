import Foundation

/// A per-document-type numbering sequence with a format template. Templates
/// support `{YYYY}`, `{YY}`, `{MM}`, and `{seq}` / `{seq:N}` (zero-padded to N).
/// The counter is monotonic; formatting is pure so it's fully testable.
public struct NumberSequence: Sendable, Equatable, Hashable, Codable {
    public var type: DocumentType
    public var template: String
    public var nextValue: Int

    public init(type: DocumentType, template: String, nextValue: Int = 1) {
        self.type = type
        self.template = template
        self.nextValue = nextValue
    }

    public static func defaultTemplate(for type: DocumentType) -> String {
        switch type {
        case .invoice: return "INV-{YYYY}-{seq:04}"
        case .estimate: return "EST-{YYYY}-{seq:04}"
        case .creditNote: return "CN-{YYYY}-{seq:04}"
        }
    }

    /// Render the number for `nextValue` on a given date, without advancing.
    public func peek(on date: CalendarDate) -> String {
        Self.render(template: template, sequence: nextValue, date: date)
    }

    /// Render the current number and return the advanced sequence.
    public mutating func advance(on date: CalendarDate) -> String {
        let rendered = peek(on: date)
        nextValue += 1
        return rendered
    }

    static func render(template: String, sequence: Int, date: CalendarDate) -> String {
        var result = template
        let replacements: [(String, String)] = [
            ("{YYYY}", String(format: "%04d", date.year)),
            ("{YY}", String(format: "%02d", date.year % 100)),
            ("{MM}", String(format: "%02d", date.month)),
            ("{DD}", String(format: "%02d", date.day)),
        ]
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }
        result = replaceSequence(in: result, sequence: sequence)
        return result
    }

    /// Replace `{seq}` and `{seq:N}` with the (optionally zero-padded) counter.
    private static func replaceSequence(in template: String, sequence: Int) -> String {
        var output = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{seq") {
            output += rest[rest.startIndex..<open.lowerBound]
            let afterTag = rest[open.upperBound...]
            guard let close = afterTag.firstIndex(of: "}") else {
                output += rest[open.lowerBound...]
                return output
            }
            let inside = afterTag[afterTag.startIndex..<close]
            if inside.hasPrefix(":"), let width = Int(inside.dropFirst()) {
                output += String(format: "%0\(width)d", sequence)
            } else {
                output += String(sequence)
            }
            rest = afterTag[afterTag.index(after: close)...]
        }
        output += rest
        return output
    }
}

import Foundation

/// A minimal, dependency-free XML element tree and serializer. EN 16931 CII and
/// Peppol UBL are order-sensitive (their XSDs are `xsd:sequence`), so the writer
/// preserves child insertion order and emits canonical, pretty-printed output
/// with correct entity escaping. No Foundation XML APIs — this builds on Linux.
public final class XMLBuilder {
    public let name: String
    public private(set) var attributes: [(String, String)]
    public private(set) var children: [XMLBuilder]
    public private(set) var text: String?

    public init(_ name: String, text: String? = nil) {
        self.name = name
        self.attributes = []
        self.children = []
        self.text = text
    }

    @discardableResult
    public func attr(_ name: String, _ value: String) -> XMLBuilder {
        attributes.append((name, value))
        return self
    }

    @discardableResult
    public func attr(_ name: String, _ value: String?) -> XMLBuilder {
        if let value { attributes.append((name, value)) }
        return self
    }

    @discardableResult
    public func add(_ child: XMLBuilder) -> XMLBuilder {
        children.append(child)
        return self
    }

    @discardableResult
    public func add(_ nodes: [XMLBuilder]) -> XMLBuilder {
        children.append(contentsOf: nodes)
        return self
    }

    /// Append a child element carrying only text, skipping it entirely when the
    /// value is `nil` (the idiom for optional EN 16931 business terms).
    @discardableResult
    public func element(_ name: String, _ value: String?) -> XMLBuilder {
        guard let value else { return self }
        children.append(XMLBuilder(name, text: value))
        return self
    }

    public func serialize(declaration: Bool = true) -> String {
        var out = declaration ? "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" : ""
        write(into: &out, indent: 0)
        return out
    }

    private func write(into out: inout String, indent: Int) {
        let pad = String(repeating: "  ", count: indent)
        out += pad + "<" + name
        for (key, value) in attributes {
            out += " " + key + "=\"" + XMLBuilder.escapeAttribute(value) + "\""
        }
        if children.isEmpty && (text == nil || text!.isEmpty) {
            if text != nil {
                out += "></" + name + ">\n"
            } else {
                out += "/>\n"
            }
            return
        }
        if children.isEmpty, let text {
            out += ">" + XMLBuilder.escapeText(text) + "</" + name + ">\n"
            return
        }
        out += ">\n"
        for child in children {
            child.write(into: &out, indent: indent + 1)
        }
        out += pad + "</" + name + ">\n"
    }

    public static func escapeText(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            default: r.append(ch)
            }
        }
        return r
    }

    static func escapeAttribute(_ s: String) -> String {
        var r = ""
        r.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": r += "&amp;"
            case "<": r += "&lt;"
            case ">": r += "&gt;"
            case "\"": r += "&quot;"
            case "\n": r += "&#10;"
            default: r.append(ch)
            }
        }
        return r
    }
}

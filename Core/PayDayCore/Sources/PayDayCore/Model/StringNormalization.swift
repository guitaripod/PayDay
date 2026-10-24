import Foundation

extension String {
    /// The VAT identifier on the wire form (BT-31 / BT-48): all whitespace
    /// removed and uppercased, so "de 123 456 789" → "DE123456789". The editors
    /// store this and the XML writers emit it, so the human and the machine
    /// never disagree on the number.
    public var normalizedVATID: String {
        filter { !$0.isWhitespace }.uppercased()
    }

    /// The email trimmed of surrounding whitespace (BT-43 / BT-58). Case is
    /// preserved — the local part is technically case-sensitive — but the
    /// stray spaces a keyboard inserts are dropped.
    public var normalizedEmail: String {
        trimmed
    }
}

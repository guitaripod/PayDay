import Foundation

/// A monetary amount as integer minor units plus its currency. Never a
/// `Double`. Intermediate computations (quantity × price, base × VAT rate) run
/// in `Decimal` and are rounded back into `Money` at the EN 16931-defined
/// boundaries via ``init(rounding:in:)``.
public struct Money: Sendable, Equatable, Hashable, Codable, Comparable {
    public let minorUnits: Int
    public let currency: Currency

    public init(minorUnits: Int, currency: Currency) {
        self.minorUnits = minorUnits
        self.currency = currency
    }

    public static func zero(_ currency: Currency) -> Money {
        Money(minorUnits: 0, currency: currency)
    }

    /// Round a raw decimal amount into whole minor units, half-up away from
    /// zero — the rounding EN 16931 validators accept for monetary terms.
    public init(rounding amount: Decimal, in currency: Currency) {
        guard !amount.isNaN else {
            self.minorUnits = 0
            self.currency = currency
            return
        }
        let scaled = amount * currency.scale
        var input = scaled
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        self.minorUnits = (rounded as NSDecimalNumber).intValue
        self.currency = currency
    }

    /// The amount as a `Decimal` (e.g. 1234 minor units, 2 digits → 12.34).
    public var amount: Decimal {
        Decimal(minorUnits) / currency.scale
    }

    /// Fixed-point decimal string with exactly the currency's minor-unit
    /// digits and a `.` separator — the form EN 16931 / UBL require, locale
    /// independent.
    public var canonicalString: String {
        let negative = minorUnits < 0
        let digits = currency.minorUnitDigits
        var units = String(abs(minorUnits))
        if digits == 0 {
            return (negative ? "-" : "") + units
        }
        if units.count <= digits {
            units = String(repeating: "0", count: digits - units.count + 1) + units
        }
        let split = units.index(units.endIndex, offsetBy: -digits)
        let whole = units[units.startIndex..<split]
        let frac = units[split..<units.endIndex]
        return (negative ? "-" : "") + whole + "." + frac
    }

    public var isZero: Bool { minorUnits == 0 }
    public var isNegative: Bool { minorUnits < 0 }

    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "currency mismatch \(lhs.currency.code) vs \(rhs.currency.code)")
        return Money(minorUnits: lhs.minorUnits + rhs.minorUnits, currency: lhs.currency)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "currency mismatch \(lhs.currency.code) vs \(rhs.currency.code)")
        return Money(minorUnits: lhs.minorUnits - rhs.minorUnits, currency: lhs.currency)
    }

    public static prefix func - (value: Money) -> Money {
        Money(minorUnits: -value.minorUnits, currency: value.currency)
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency, "currency mismatch \(lhs.currency.code) vs \(rhs.currency.code)")
        return lhs.minorUnits < rhs.minorUnits
    }

    public static func sum(_ values: [Money], currency: Currency) -> Money {
        values.reduce(Money.zero(currency), +)
    }
}

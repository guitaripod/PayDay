import Foundation

/// A timezone-free calendar date (year/month/day). Invoices carry date-only
/// terms (issue date, due date, delivery date); modelling them without a
/// `Date`/`TimeZone` keeps the Kit deterministic across hosts and gives exact
/// control over the `YYYYMMDD` (CII) and `YYYY-MM-DD` (UBL) wire formats.
public struct CalendarDate: Sendable, Equatable, Hashable, Codable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 1970
        self.month = c.month ?? 1
        self.day = c.day ?? 1
    }

    /// CII / UN/CEFACT date string, format qualifier 102.
    public var ciiString: String {
        String(format: "%04d%02d%02d", year, month, day)
    }

    /// UBL / ISO 8601 date string.
    public var iso8601: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public func adding(days: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> CalendarDate {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let base = calendar.date(from: comps),
              let shifted = calendar.date(byAdding: .day, value: days, to: base)
        else { return self }
        return CalendarDate(shifted, calendar: calendar)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

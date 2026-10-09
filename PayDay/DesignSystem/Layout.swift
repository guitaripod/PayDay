import UIKit
import PayDayKit

extension UIView {
    func pinEdges(to other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }

    func pinEdges(toSafeAreaOf other: UIView, insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        let guide = other.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: guide.topAnchor, constant: insets.top),
            leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -insets.right),
            bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -insets.bottom),
        ])
    }
}

enum ColumnWidth {
    static let form: CGFloat = 560
    static let document: CGFloat = 720
    static let dashboard: CGFloat = 1100
}

extension UIScrollView {
    /// Hosts `column` as a vertically scrolling, horizontally centred column no
    /// wider than `maxWidth`, so a form or stack reads as a column on the inner
    /// display instead of stretching across it. Narrow windows keep `insets`.
    func embedColumn(_ column: UIView, maxWidth: CGFloat, insets: UIEdgeInsets) {
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        let fill = column.widthAnchor.constraint(
            equalTo: frameLayoutGuide.widthAnchor, constant: -(insets.left + insets.right))
        fill.priority = UILayoutPriority(850)
        NSLayoutConstraint.activate([
            contentLayoutGuide.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
            column.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: insets.top),
            column.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor, constant: -insets.bottom),
            column.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
            column.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            fill,
        ])
    }
}

/// Locale-aware money + date formatting for the UI. Machine-facing strings come
/// from `Money.canonicalString` / `CalendarDate`; these are for humans only.
enum Format {
    static func money(_ money: Money, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = money.currency.code
        formatter.locale = locale
        formatter.maximumFractionDigits = money.currency.minorUnitDigits
        formatter.minimumFractionDigits = money.currency.minorUnitDigits
        return formatter.string(from: money.amount as NSDecimalNumber)
            ?? "\(money.currency.code) \(money.canonicalString)"
    }

    static func date(_ date: CalendarDate, style: DateFormatter.Style = .medium, locale: Locale = .current) -> String {
        var comps = DateComponents()
        comps.year = date.year
        comps.month = date.month
        comps.day = date.day
        let calendar = Calendar(identifier: .gregorian)
        guard let resolved = calendar.date(from: comps) else { return date.iso8601 }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: resolved)
    }

    static func today(calendar: Calendar = Calendar(identifier: .gregorian)) -> CalendarDate {
        CalendarDate(Date(), calendar: calendar)
    }
}

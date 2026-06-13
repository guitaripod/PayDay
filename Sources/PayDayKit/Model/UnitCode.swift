import Foundation

/// UN/ECE Recommendation 20 unit-of-measure codes (BT-130). A small, practical
/// subset for a service-and-goods invoice app. The `rawValue` is the code that
/// goes onto the wire; `label` is what a human sees.
public enum UnitCode: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case piece = "H87"
    case hour = "HUR"
    case day = "DAY"
    case month = "MON"
    case kilogram = "KGM"
    case litre = "LTR"
    case metre = "MTR"
    case squareMetre = "MTK"
    case kilometre = "KMT"
    case lumpSum = "LS"
    case word = "E37"

    public var label: String {
        switch self {
        case .piece: return "piece"
        case .hour: return "hour"
        case .day: return "day"
        case .month: return "month"
        case .kilogram: return "kg"
        case .litre: return "litre"
        case .metre: return "metre"
        case .squareMetre: return "m²"
        case .kilometre: return "km"
        case .lumpSum: return "lump sum"
        case .word: return "word"
        }
    }
}

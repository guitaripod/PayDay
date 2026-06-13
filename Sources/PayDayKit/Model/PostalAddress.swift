import Foundation

/// A structured postal address. `countryCode` is ISO 3166-1 alpha-2 and is the
/// load-bearing field for EN 16931 (BT-40 / BT-55) and for deciding VAT
/// treatment (domestic / intra-EU / export).
public struct PostalAddress: Sendable, Equatable, Hashable, Codable {
    public var line1: String
    public var line2: String
    public var city: String
    public var postalCode: String
    public var region: String
    public var countryCode: String

    public init(
        line1: String = "",
        line2: String = "",
        city: String = "",
        postalCode: String = "",
        region: String = "",
        countryCode: String = ""
    ) {
        self.line1 = line1
        self.line2 = line2
        self.city = city
        self.postalCode = postalCode
        self.region = region
        self.countryCode = countryCode.uppercased()
    }

    public var isEmpty: Bool {
        line1.isEmpty && city.isEmpty && postalCode.isEmpty && countryCode.isEmpty
    }

    public var singleLine: String {
        [line1, line2, [postalCode, city].filter { !$0.isEmpty }.joined(separator: " "), region, countryCode]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

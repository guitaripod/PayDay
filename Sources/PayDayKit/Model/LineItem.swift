import Foundation

/// A single invoice line (BG-25). Quantities and unit prices are `Decimal` to
/// allow fractional hours and four-decimal net prices (BT-146); the line's net
/// monetary amount (BT-131) is produced by the tax engine, rounded to the
/// document currency.
public struct LineItem: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var details: String
    public var quantity: Decimal
    public var unit: UnitCode
    /// BT-146 — the net price of one unit, before line-level VAT.
    public var unitPrice: Decimal
    /// A per-line percentage discount (0...100), applied to the gross line.
    public var discountPercent: Decimal
    public var vatCategory: VATCategory
    /// BT-152 — the VAT rate as a percentage (e.g. 24 for 24%).
    public var vatRatePercent: Decimal

    public init(
        id: String,
        name: String,
        details: String = "",
        quantity: Decimal = 1,
        unit: UnitCode = .piece,
        unitPrice: Decimal = 0,
        discountPercent: Decimal = 0,
        vatCategory: VATCategory = .standard,
        vatRatePercent: Decimal = 0
    ) {
        self.id = id
        self.name = name
        self.details = details
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.discountPercent = discountPercent
        self.vatCategory = vatCategory
        self.vatRatePercent = vatRatePercent
    }

    /// The raw (unrounded) net of the line: quantity × unitPrice × (1 − discount).
    /// Rounding into the document currency is the tax engine's responsibility.
    public var rawNet: Decimal {
        let gross = quantity * unitPrice
        guard discountPercent != 0 else { return gross }
        let factor = (100 - discountPercent) / 100
        return gross * factor
    }

    /// The effective VAT rate the engine should apply, honouring the rule that
    /// non-standard categories are always zero rated regardless of the field.
    public var effectiveRate: Decimal {
        vatCategory.allowsPositiveRate ? vatRatePercent : 0
    }
}

import Foundation

/// Computes an invoice's monetary picture per EN 16931's rounding and
/// summation rules. The contract validators check:
///
/// - Each line net (BT-131) is rounded to the document currency.
/// - A VAT breakdown groups lines by (category, rate); the group's taxable base
///   (BT-116) is the **sum of the rounded line nets** in that group, so
///   `BT-116 = Σ BT-131` holds exactly. The group VAT (BT-117) is then
///   `round(BT-116 × rate / 100)` — computed once on the group, never per line.
/// - BT-106 = Σ line nets; BT-109 = BT-106 − allowances + charges;
///   BT-110 = Σ group VAT; BT-112 = BT-109 + BT-110; BT-115 = BT-112 − prepaid.
public enum TaxEngine {
    public static func compute(_ invoice: Invoice) -> ComputedTotals {
        let currency = invoice.currency
        let lineNets = invoice.lines.map { Money(rounding: $0.rawNet, in: currency) }

        var groups: [GroupKey: GroupAccumulator] = [:]
        var order: [GroupKey] = []

        func accumulate(_ net: Money, category: VATCategory, rate: Decimal, reason: String) {
            let key = GroupKey(category: category, rate: rate)
            if var existing = groups[key] {
                existing.base = existing.base + net
                groups[key] = existing
            } else {
                groups[key] = GroupAccumulator(base: net, reason: reason)
                order.append(key)
            }
        }

        for (index, line) in invoice.lines.enumerated() {
            accumulate(
                lineNets[index],
                category: line.vatCategory,
                rate: line.effectiveRate,
                reason: line.vatCategory.defaultExemptionReason)
        }

        var allowanceTotal = Money.zero(currency)
        var chargeTotal = Money.zero(currency)
        for adjustment in invoice.adjustments {
            let rounded = Money(rounding: adjustment.amount, in: currency)
            let rate = adjustment.vatCategory.allowsPositiveRate ? adjustment.vatRatePercent : 0
            let signed = adjustment.isCharge ? rounded : -rounded
            accumulate(
                signed,
                category: adjustment.vatCategory,
                rate: rate,
                reason: adjustment.vatCategory.defaultExemptionReason)
            if adjustment.isCharge { chargeTotal = chargeTotal + rounded }
            else { allowanceTotal = allowanceTotal + rounded }
        }

        let breakdowns: [TaxBreakdown] = order.map { key in
            let acc = groups[key]!
            let tax = Money(rounding: acc.base.amount * key.rate / 100, in: currency)
            return TaxBreakdown(
                category: key.category,
                ratePercent: key.rate,
                taxableBase: acc.base,
                taxAmount: tax,
                exemptionReason: acc.reason)
        }

        let lineTotal = Money.sum(lineNets, currency: currency)
        let taxExclusive = lineTotal - allowanceTotal + chargeTotal
        let taxTotal = Money.sum(breakdowns.map(\.taxAmount), currency: currency)
        let taxInclusive = taxExclusive + taxTotal
        let prepaid = invoice.prepaidMoney
        let payable = taxInclusive - prepaid

        let summary = MonetarySummary(
            lineTotal: lineTotal,
            allowanceTotal: allowanceTotal,
            chargeTotal: chargeTotal,
            taxExclusiveTotal: taxExclusive,
            taxTotal: taxTotal,
            taxInclusiveTotal: taxInclusive,
            prepaidAmount: prepaid,
            payableAmount: payable)

        return ComputedTotals(
            currency: currency,
            lineNets: lineNets,
            breakdowns: breakdowns,
            summary: summary)
    }

    private struct GroupKey: Hashable {
        let category: VATCategory
        let rate: Decimal
    }

    private struct GroupAccumulator {
        var base: Money
        let reason: String
    }
}

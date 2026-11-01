import Foundation
import StoreKit

/// One Pro plan as the paywall shows it, read from the StoreKit product: the localized price, the billing period and the
/// free trial the customer may still use. Nothing here is a price or a term the code decided.
struct ProPlan: Equatable, Identifiable, Sendable {
    enum Period: Sendable {
        case monthly
        case annual
    }

    /// The product id.
    let id: String
    let localizedPrice: String
    /// The price as a number, in the storefront's currency, for comparing plans.
    let price: Decimal
    let period: Period
    /// The length of the free introductory offer in days, or nil when the product has none.
    let trialDays: Int?
    /// Whether the customer's group is still eligible for the introductory offer.
    let trialEligible: Bool

    /// Nil for a product that is not a one month or one year auto-renewable subscription.
    init?(product: Product, trialEligible: Bool) {
        guard let subscription = product.subscription, let period = Self.period(of: subscription.subscriptionPeriod) else {
            return nil
        }
        self.init(
            id: product.id,
            localizedPrice: product.displayPrice,
            price: product.price,
            period: period,
            trialDays: Self.trialDays(of: subscription.introductoryOffer),
            trialEligible: trialEligible
        )
    }

    init(id: String, localizedPrice: String, price: Decimal, period: Period, trialDays: Int?, trialEligible: Bool) {
        self.id = id
        self.localizedPrice = localizedPrice
        self.price = price
        self.period = period
        self.trialDays = trialDays
        self.trialEligible = trialEligible
    }

    /// What the annual plan saves against twelve months of the monthly one, in whole percent rounded down so the claim
    /// is never generous; nil when either plan is missing or the annual one saves nothing.
    static func annualSavingsPercent(in plans: [ProPlan]) -> Int? {
        guard let annual = plans.first(where: { $0.period == .annual })?.price,
              let monthly = plans.first(where: { $0.period == .monthly })?.price, monthly > 0
        else { return nil }
        let year = monthly * 12
        guard annual < year else { return nil }
        let percent = Int(NSDecimalNumber(decimal: (year - annual) / year * 100).doubleValue.rounded(.down))
        return percent >= 1 ? percent : nil
    }

    private static func period(of period: Product.SubscriptionPeriod) -> Period? {
        switch (period.unit, period.value) {
        case (.month, 1): return .monthly
        case (.year, 1): return .annual
        default: return nil
        }
    }

    /// Only free trials count: a paid introductory offer is not part of what the paywall presents.
    private static func trialDays(of offer: Product.SubscriptionOffer?) -> Int? {
        guard let offer, offer.paymentMode == .freeTrial else { return nil }
        let units = offer.period.value * offer.periodCount
        switch offer.period.unit {
        case .day: return units
        case .week: return units * 7
        case .month: return units * 30
        case .year: return units * 365
        @unknown default: return nil
        }
    }
}

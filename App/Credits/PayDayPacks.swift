import Foundation
import MidgarCommerce
import MidgarCredits

/// What Pay Day sells, in one place: the store configuration, the credits configuration and the tests all read this
/// table. The pack ids and amounts are mako's catalog for the `payday` tenant, and mako requires each product id to be
/// its `rc_product_prefix` (`com.guitaripod.payday.credits.`) plus the pack id. The Pro subscriptions grant the registry's
/// `pro` entitlement. Prices are StoreKit's, from the App Store records and `Products.storekit`. Changing an id, an
/// amount or a price is the founder's decision.
nonisolated enum PayDayPacks {
    static let starter = MidgarCreditsPack(id: "starter", productID: "com.guitaripod.payday.credits.starter", credits: 30)
    static let regular = MidgarCreditsPack(id: "regular", productID: "com.guitaripod.payday.credits.regular", credits: 110)
    static let propack = MidgarCreditsPack(id: "propack", productID: "com.guitaripod.payday.credits.propack", credits: 300)
    static let business = MidgarCreditsPack(id: "business", productID: "com.guitaripod.payday.credits.business", credits: 650)

    static let all = [starter, regular, propack, business]

    /// The names mako's catalog gives the packs, which the credit store shows above the credits each one grants.
    static func name(of pack: MidgarCreditsPack) -> String {
        switch pack.id {
        case starter.id: return "Starter"
        case regular.id: return "Regular"
        case propack.id: return "Pro Pack"
        case business.id: return "Business"
        default: return pack.id
        }
    }

    static let packProductIDs = all.map(\.productID)

    static let proAnnualProductID = "com.guitaripod.payday.pro.annual"
    static let proMonthlyProductID = "com.guitaripod.payday.pro.monthly"

    /// The Pro plans in the order the paywall lists them.
    static let proProductIDs = [proAnnualProductID, proMonthlyProductID]

    /// The entitlement every Pro plan grants, as the registry's `[commerce]` table names it.
    static let proEntitlement = "pro"

    /// The store sells the two Pro plans, which grant `pro`, and the four consumable packs, which grant nothing.
    static func storeConfiguration(directory: URL? = nil) -> MidgarStoreConfiguration {
        MidgarStoreConfiguration(
            appID: PayDayMidgar.appID,
            productIDs: proProductIDs + packProductIDs,
            entitlementsByProduct: Dictionary(uniqueKeysWithValues: proProductIDs.map { ($0, proEntitlement) }),
            mode: .purchases,
            directory: directory
        )
    }

    /// The wallet's packs. `isProductionLaunch` decides whether the Apple Ads attribution is reported: only the shipped
    /// app does, never a debug build, a test host or a demo capture.
    static func creditsConfiguration(
        directory: URL? = nil,
        attributionTokenProvider: any MidgarAdAttributionTokenProviding = MidgarAdServicesTokenProvider(),
        isProductionLaunch: @escaping @Sendable () -> Bool = { PayDayMidgar.isProductionLaunch }
    ) -> MidgarCreditsConfiguration {
        MidgarCreditsConfiguration(
            packs: all,
            directory: directory,
            attributionTokenProvider: attributionTokenProvider,
            isProductionLaunch: isProductionLaunch
        )
    }
}

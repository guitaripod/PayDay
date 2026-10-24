import Combine
import Foundation
import MidgarCommerce
import MidgarCore
import StoreKit

/// What ``ProAccess`` asks of the purchase engine. ``MidgarStore`` is the production conformance; a test passes a store
/// that answers however it needs to.
protocol ProStoring: Sendable {
    func isEntitled(to name: String) async -> Bool
    func purchase(_ productID: String) async throws -> MidgarPurchaseResult
    func restore() async throws
    func refresh() async
    func events() async -> AsyncStream<MidgarStoreEvent>
}

extension MidgarStore: ProStoring {}

/// What a purchase of a Pro plan came to, for the paywall.
enum ProPurchaseOutcome: Equatable {
    case purchased
    /// Ask to Buy or another approval is pending. Pro unlocks by itself when the approval arrives.
    case pending
    /// The customer backed out: nothing is shown.
    case cancelled
    case failed(String)
}

/// What a restore came to, for the paywall.
enum ProRestoreOutcome: Equatable {
    case restored
    case nothingToRestore
    case failed(String)
}

/// Whether this person has Pro, and the plans the paywall sells. The purchase engine is MidgarStore: it buys, finishes,
/// listens to `Transaction.updates` and reports to the ledger, and its entitlements are the ledger's answer for the Midgar
/// ID united with StoreKit's current entitlements on this device, so a Pro owner stays Pro offline and every plan bought
/// before the move (the old SDK only ever sold Apple's own transactions) still counts.
///
/// `isPro` follows the store's `entitlementsChanged` and `purchaseApproved` events and is read again after a purchase and a
/// restore, so an Ask to Buy plan unlocks when it is approved without the paywall doing anything. Where the app reaches no
/// Midgar service (a test host, a demo capture) there is no store and Pro stays off.
@MainActor
final class ProAccess: ObservableObject {
    static let shared = ProAccess(store: PayDayMidgar.shared.store)

    @Published private(set) var isPro = false
    @Published private(set) var plans: [ProPlan] = []

    private let store: (any ProStoring)?
    private let entitlement: String
    private var eventsTask: Task<Void, Never>?

    init(store: (any ProStoring)?, entitlement: String = PayDayPacks.proEntitlement) {
        self.store = store
        self.entitlement = entitlement
        guard let store else { return }
        eventsTask = Task { [weak self] in
            for await event in await store.events() {
                await self?.handle(event)
            }
        }
        Task { [weak self] in await self?.refresh() }
    }

    /// Reads the entitlement from the store and returns whether the person has Pro. A host without a store answers false.
    @discardableResult
    func refresh() async -> Bool {
        guard let store else { return false }
        let entitled = await store.isEntitled(to: entitlement)
        if entitled != isPro {
            isPro = entitled
            MidgarLog.info("pro \(entitled ? "on" : "off")", category: .credits)
        }
        return entitled
    }

    /// Loads the Pro plans in the order the paywall lists them, with the free trial the customer may still use. A plan
    /// StoreKit does not sell is left out; a failure keeps the plans already loaded.
    func loadPlans() async {
        do {
            let products = try await Product.products(for: PayDayPacks.proProductIDs)
            var loaded: [ProPlan] = []
            for id in PayDayPacks.proProductIDs {
                guard let product = products.first(where: { $0.id == id }) else { continue }
                let eligible = await product.subscription?.isEligibleForIntroOffer ?? false
                if let plan = ProPlan(product: product, trialEligible: eligible) {
                    loaded.append(plan)
                }
            }
            plans = loaded
        } catch {
            MidgarLog.error("pro plans failed to load: \(error)", category: .credits)
        }
    }

    /// Buys a plan through the purchase engine, which carries the Midgar ID as `appAccountToken`.
    func purchase(_ plan: ProPlan) async -> ProPurchaseOutcome {
        guard let store else { return .failed(ProMessage.unavailable) }
        do {
            switch try await store.purchase(plan.id) {
            case .purchased:
                await refresh()
                return .purchased
            case .pending:
                return .pending
            case .cancelled:
                return .cancelled
            }
        } catch {
            ReviewPrompt.notePurchaseFailure()
            MidgarLog.error("pro purchase failed: \(error)", category: .credits)
            return ProMessage.text(for: error).map(ProPurchaseOutcome.failed) ?? .cancelled
        }
    }

    /// Asks the App Store to sync and reads the entitlement again.
    func restore() async -> ProRestoreOutcome {
        do {
            try await restoreStore()
        } catch {
            MidgarLog.error("pro restore failed: \(error)", category: .credits)
            return .failed(ProMessage.text(for: error) ?? ProMessage.unavailable)
        }
        return isPro ? .restored : .nothingToRestore
    }

    /// The App Store sync and the entitlement read the credit store's Restore Purchases runs too.
    func restoreStore() async throws {
        guard let store else { return }
        try await store.restore()
        await refresh()
    }

    private func handle(_ event: MidgarStoreEvent) async {
        switch event {
        case .entitlementsChanged, .purchaseApproved:
            await refresh()
        case .refused(let productID):
            MidgarLog.error("store refused an unverified transaction for \(productID)", category: .credits)
        }
    }
}

/// Turns a failed purchase or restore into a sentence worth showing, or nothing when the person simply backed out.
enum ProMessage {
    static var unavailable: String {
        String(localized: "The purchase didn't go through. Try again in a moment.")
    }

    static func text(for error: any Error) -> String? {
        guard let store = error as? MidgarStoreError else {
            return unavailable
        }
        switch store {
        case .unverifiedTransaction:
            return String(localized: "The App Store couldn't verify this purchase. Try again, or choose Restore Purchases.")
        case .storeKit(let description) where description.contains("userCancelled"):
            return nil
        case .storeKit(let description) where description.contains("networkError"):
            return String(localized: "Can't reach the App Store. Check your connection and try again.")
        case .storeKit(let description) where description.contains("notAvailableInStorefront"):
            return String(localized: "This plan isn't available in your country or region.")
        default:
            return unavailable
        }
    }
}

import Foundation
import MidgarCommerce
import MidgarCore
import StoreKit
import StoreKitTest
import Testing
@testable import PayDay

extension StoreBacked {
    /// Buys Pay Day Pro through `ProAccess` on a MidgarStore with the app's own configuration, against
    /// `Products.storekit`, so the plans, prices, trial and entitlement mapping the app ships are checked together on a
    /// real StoreKit. The gateway is a `URLProtocol` stub that knows the Midgar ID, holds no entitlement and answers every
    /// report. A test session signs its transactions with Xcode's local certificate, so the store never reports them to
    /// the ledger. The first purchase on a fresh simulator can stall: rerun once.
    @MainActor
    @Suite(.timeLimit(.minutes(3)))
    struct ProPurchases {
        private struct Harness {
            let store: MidgarStore
            let access: ProAccess
            let session: SKTestSession
            let directory: URL

            func stop() async {
                await store.stop()
                try? FileManager.default.removeItem(at: directory)
            }
        }

        private func makeHarness(askToBuy: Bool = false, buyingWith override: (any ProStoring)? = nil) throws -> Harness {
            let session = try SKTestSession(contentsOf: StoreKitFile.url)
            session.resetToDefaultState()
            session.clearTransactions()
            session.disableDialogs = true
            session.askToBuyEnabled = askToBuy
            CreditsGatewayStub.reset()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("payday-pro-" + UUID().uuidString, isDirectory: true)
            let store = MidgarStore(
                configuration: PayDayPacks.storeConfiguration(directory: directory),
                identity: StubIdentity(),
                http: MidgarHTTPClient(configuration: CreditsGatewayStub.httpConfiguration())
            )
            let access = ProAccess(store: override ?? SceneAnchoredStore(store: store))
            return Harness(store: store, access: access, session: session, directory: directory)
        }

        /// The verified entitlement StoreKit holds for the product, read from `currentEntitlements` because `latest` can lag
        /// behind a purchase a test session just made.
        private func currentEntitlement(for productID: String) async -> Transaction? {
            for await result in Transaction.currentEntitlements {
                if case .verified(let transaction) = result, transaction.productID == productID {
                    return transaction
                }
            }
            return nil
        }

        private func plan(_ productID: String, in access: ProAccess) async throws -> ProPlan {
            await access.loadPlans()
            return try #require(access.plans.first { $0.id == productID })
        }

        @Test func theConfigurationFileSellsTheTwoPlansInOneGroupAtTheirPrices() throws {
            let file = try StoreKitFile.load()
            let plans = Dictionary(uniqueKeysWithValues: file.subscriptionGroups.flatMap(\.subscriptions).map { ($0.productID, $0) })

            #expect(file.subscriptionGroups.map(\.name) == ["Pay Day Pro"])
            #expect(plans["com.guitaripod.payday.pro.annual"]?.displayPrice == "39.99")
            #expect(plans["com.guitaripod.payday.pro.monthly"]?.displayPrice == "4.99")
            #expect(plans["com.guitaripod.payday.pro.annual"]?.referenceName == "Pay Day Pro Annual")
            #expect(plans["com.guitaripod.payday.pro.monthly"]?.referenceName == "Pay Day Pro Monthly")
        }

        @Test func thePaywallPlansAreAnnualThenMonthlyWithTheAnnualWeekLongTrial() async throws {
            let harness = try makeHarness()

            await harness.access.loadPlans()

            #expect(harness.access.plans.map(\.id) == PayDayPacks.proProductIDs)
            let annual = try #require(harness.access.plans.first)
            let monthly = try #require(harness.access.plans.last)
            #expect(annual.period == .annual)
            #expect(annual.localizedPrice == "$39.99")
            #expect(annual.trialDays == 7)
            #expect(annual.trialEligible)
            #expect(monthly.period == .monthly)
            #expect(monthly.localizedPrice == "$4.99")
            #expect(monthly.trialDays == nil)
            await harness.stop()
        }

        @Test func buyingTheMonthlyPlanGrantsProAndCarriesTheMidgarID() async throws {
            let harness = try makeHarness()
            let monthly = try await plan(PayDayPacks.proMonthlyProductID, in: harness.access)
            #expect(!harness.access.isPro)

            let outcome = await harness.access.purchase(monthly)

            #expect(outcome == .purchased)
            #expect(harness.access.isPro)
            #expect(await harness.store.isEntitled(to: PayDayPacks.proEntitlement))
            let bought = try #require(harness.session.allTransactions().first { $0.productIdentifier == monthly.id })
            let transaction = try #require(await currentEntitlement(for: monthly.id))
            #expect(UInt(transaction.id) == UInt(bought.identifier))
            #expect(transaction.appAccountToken == UUID(uuidString: StubIdentity.midgarID))
            #expect(CreditsGatewayStub.requests(method: "POST", pathSuffix: "/v1/ledger/transactions").isEmpty)
            await harness.stop()
        }

        @Test func buyingTheAnnualPlanGrantsPro() async throws {
            let harness = try makeHarness()
            let annual = try await plan(PayDayPacks.proAnnualProductID, in: harness.access)

            let outcome = await harness.access.purchase(annual)

            #expect(outcome == .purchased)
            #expect(harness.access.isPro)
            await harness.stop()
        }

        @Test func aRestoreFindsAnEarlierPurchase() async throws {
            let harness = try makeHarness()
            try harness.session.buyProduct(productIdentifier: PayDayPacks.proMonthlyProductID)

            let outcome = await harness.access.restore()

            #expect(outcome == .restored)
            #expect(harness.access.isPro)
            await harness.stop()
        }

        @Test func aRestoreWithNothingBoughtSaysSo() async throws {
            let harness = try makeHarness()

            let outcome = await harness.access.restore()

            #expect(outcome == .nothingToRestore)
            #expect(!harness.access.isPro)
            await harness.stop()
        }

        @Test func aRefundedPlanTakesProAway() async throws {
            let harness = try makeHarness()
            let monthly = try await plan(PayDayPacks.proMonthlyProductID, in: harness.access)
            _ = await harness.access.purchase(monthly)
            #expect(harness.access.isPro)

            let transaction = try #require(harness.session.allTransactions().first)
            try harness.session.refundTransaction(identifier: UInt(transaction.identifier))

            #expect(await eventually { !harness.access.isPro })
            await harness.stop()
        }

        @Test func askToBuyIsPendingUntilApprovedThenUnlocksProByItself() async throws {
            let harness = try makeHarness(askToBuy: true)
            let monthly = try await plan(PayDayPacks.proMonthlyProductID, in: harness.access)

            let outcome = await harness.access.purchase(monthly)

            #expect(outcome == .pending)
            #expect(!harness.access.isPro)
            let waiting = try #require(harness.session.allTransactions().first)
            try harness.session.approveAskToBuyTransaction(identifier: UInt(waiting.identifier))

            #expect(await eventually { harness.access.isPro })
            await harness.stop()
        }

        @Test func aCancelledPurchaseShowsNothing() async throws {
            let harness = try makeHarness(buyingWith: CancellingStore())
            let monthly = ProPlan(
                id: PayDayPacks.proMonthlyProductID, localizedPrice: "$4.99", period: .monthly, trialDays: nil, trialEligible: false)

            let outcome = await harness.access.purchase(monthly)

            #expect(outcome == .cancelled)
            #expect(!harness.access.isPro)
            await harness.stop()
        }

        @Test func aStoreKitFailureIsASentenceAndGrantsNothing() async throws {
            let harness = try makeHarness()
            let monthly = try await plan(PayDayPacks.proMonthlyProductID, in: harness.access)
            try await harness.session.setSimulatedError(.generic(.unknown), forAPI: .purchase)

            let outcome = await harness.access.purchase(monthly)

            #expect(outcome == .failed(ProMessage.unavailable))
            #expect(!harness.access.isPro)
            #expect(harness.session.allTransactions().isEmpty)
            await harness.stop()
        }

        @Test func aLapsedMonthlyPlanTakesProAwayAtTheNextRefresh() async throws {
            let harness = try makeHarness()
            let monthly = try await plan(PayDayPacks.proMonthlyProductID, in: harness.access)
            _ = await harness.access.purchase(monthly)
            #expect(harness.access.isPro)

            let transaction = try #require(harness.session.allTransactions().first)
            try harness.session.disableAutoRenewForTransaction(identifier: UInt(transaction.identifier))
            try harness.session.expireSubscription(productIdentifier: PayDayPacks.proMonthlyProductID)

            #expect(await eventually {
                await harness.store.refresh()
                return !(await harness.access.refresh())
            })
            await harness.stop()
        }

        @Test func aPurchaseAnotherDeviceMadeUnlocksProThroughTheStoresEvents() async throws {
            let harness = try makeHarness()
            #expect(await harness.access.refresh() == false)

            try harness.session.buyProduct(productIdentifier: PayDayPacks.proAnnualProductID)

            #expect(await eventually { harness.access.isPro })
            await harness.stop()
        }

        @Test func aPackIsNotAPlanAndGrantsNoPro() async throws {
            let harness = try makeHarness()

            try harness.session.buyProduct(productIdentifier: PayDayPacks.starter.productID)
            await harness.store.refresh()

            #expect(!(await harness.access.refresh()))
            await harness.stop()
        }

        @Test func theMessagesForAFailedPurchaseAreSentencesAndABackedOutPurchaseIsSilent() {
            #expect(ProMessage.text(for: MidgarStoreError.storeKit("userCancelled")) == nil)
            #expect(ProMessage.text(for: MidgarStoreError.storeKit("networkError(...)")) != ProMessage.unavailable)
            #expect(ProMessage.text(for: MidgarStoreError.unverifiedTransaction(productID: "x")) != ProMessage.unavailable)
            #expect(ProMessage.text(for: MidgarStoreError.storeKit("notAvailableInStorefront")) != ProMessage.unavailable)
            #expect(ProMessage.text(for: MidgarStoreError.unknownProduct("x")) == ProMessage.unavailable)
            #expect(ProMessage.text(for: URLError(.notConnectedToInternet)) == ProMessage.unavailable)
        }

        @Test func aHostWithoutAStoreKeepsProOffAndRestoresNothing() async {
            let access = ProAccess(store: nil)

            #expect(await access.refresh() == false)
            #expect(await access.restore() == .nothingToRestore)
            #expect(!access.isPro)
        }
    }
}

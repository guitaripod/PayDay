import Foundation
import MidgarCommerce
import MidgarCore
import MidgarCredits
import StoreKitTest
import Testing
@testable import PayDay

extension StoreBacked {
    /// Buys Pay Day's credit packs through MidgarCredits on a MidgarStore with the app's own configuration, against
    /// `Products.storekit` (the file the scheme runs with), so the pack table, the StoreKit products and mako's validate
    /// request are checked together on a real StoreKit. The gateway is a `URLProtocol` stub, so nothing reaches mako. A
    /// test session signs its transactions with Xcode's local certificate, so the store never reports them to the
    /// ledger. The first purchase on a fresh simulator can stall: rerun once.
    @MainActor
    @Suite(.timeLimit(.minutes(3)))
    struct CreditPurchases {
        private nonisolated static let legacyKey = "legacy-aicredits-key"
        private static let starterProductID = "com.guitaripod.payday.credits.starter"

        private struct Harness {
            let store: MidgarStore
            let credits: MidgarCredits
            let model: CreditsModel
            let session: SKTestSession
            let directory: URL

            func stop() async {
                await credits.stop()
                await store.stop()
                try? FileManager.default.removeItem(at: directory)
            }
        }

        private func makeHarness(purchasing override: (any MidgarCreditsPurchasing)? = nil) throws -> Harness {
            let session = try SKTestSession(contentsOf: StoreKitFile.url)
            session.resetToDefaultState()
            session.clearTransactions()
            session.disableDialogs = true
            session.askToBuyEnabled = false
            CreditsGatewayStub.reset()
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("payday-credits-" + UUID().uuidString, isDirectory: true)
            let configuration = CreditsGatewayStub.httpConfiguration()
            let identity = StubIdentity()
            let store = MidgarStore(
                configuration: PayDayPacks.storeConfiguration(directory: directory),
                identity: identity,
                http: MidgarHTTPClient(configuration: configuration)
            )
            let credits = MidgarCredits(
                configuration: PayDayPacks.creditsConfiguration(directory: directory),
                http: configuration,
                identity: identity,
                purchasing: override ?? SceneAnchoredStore(store: store),
                legacyAPIKey: { Self.legacyKey }
            )
            return Harness(store: store, credits: credits, model: CreditsModel(source: credits), session: session, directory: directory)
        }

        @Test func theConfigurationFileSellsExactlyTheFourPacksAndTheTwoPlansAtTheirPrices() throws {
            let file = try StoreKitFile.load()
            let consumables = Dictionary(uniqueKeysWithValues: file.products.map { ($0.productID, $0) })

            #expect(Set(consumables.keys) == Set(PayDayPacks.packProductIDs))
            #expect(consumables.values.allSatisfy { $0.type == "Consumable" })
            #expect(consumables["com.guitaripod.payday.credits.starter"]?.displayPrice == "2.99")
            #expect(consumables["com.guitaripod.payday.credits.regular"]?.displayPrice == "9.99")
            #expect(consumables["com.guitaripod.payday.credits.propack"]?.displayPrice == "24.99")
            #expect(consumables["com.guitaripod.payday.credits.business"]?.displayPrice == "49.99")
            #expect(consumables["com.guitaripod.payday.credits.propack"]?.referenceName == "Pro Pack")
            #expect(file.subscriptionGroups.map(\.name) == ["Pay Day Pro"])
            let plans = file.subscriptionGroups.flatMap(\.subscriptions)
            #expect(Set(plans.map(\.productID)) == Set(PayDayPacks.proProductIDs))
        }

        @Test func thePackTableMatchesMakosCatalog() {
            #expect(PayDayPacks.all.map(\.id) == ["starter", "regular", "propack", "business"])
            #expect(PayDayPacks.all.map(\.credits) == [30, 110, 300, 650])
            #expect(PayDayPacks.all.map { PayDayPacks.name(of: $0) } == ["Starter", "Regular", "Pro Pack", "Business"])
            #expect(PayDayPacks.all.allSatisfy { $0.productID == "com.guitaripod.payday.credits." + $0.id })
            #expect(PayDayPacks.creditsConfiguration().productIDs == PayDayPacks.packProductIDs)
        }

        @Test func theStoreSellsThePlansAndThePacksAndGrantsProOnlyForThePlans() {
            let configuration = PayDayPacks.storeConfiguration()

            #expect(Set(configuration.productIDs) == Set(PayDayPacks.proProductIDs + PayDayPacks.packProductIDs))
            #expect(configuration.entitlementsByProduct == [
                "com.guitaripod.payday.pro.annual": "pro",
                "com.guitaripod.payday.pro.monthly": "pro",
            ])
            #expect(configuration.mode == .purchases)
            #expect(configuration.appID == "pay-day")
            #expect(configuration.crossAppEntitlements.isEmpty)
        }

        @Test func theOffersAreTheFourPacksWithStoreKitsPrices() async throws {
            let harness = try makeHarness()

            let offers = try await harness.credits.offers()

            #expect(offers.map(\.pack.id) == ["starter", "regular", "propack", "business"])
            #expect(offers.map(\.product.displayPrice) == ["$2.99", "$9.99", "$24.99", "$49.99"])
            #expect(offers.map(\.product.displayName) == ["Starter", "Regular", "Pro Pack", "Business"])
            await harness.stop()
        }

        @Test func buyingStarterCarriesTheMidgarIDAndPostsMakosValidateRoute() async throws {
            let harness = try makeHarness()
            CreditsGatewayStub.setBalance(15)
            let observing = Task { await harness.model.start() }
            #expect(await eventually { harness.model.balance == 15 })
            CreditsGatewayStub.setBalance(45)
            CreditsGatewayStub.setValidate([.credited(added: 30, newBalance: 45)])

            let result = try await harness.credits.buy("starter")

            #expect(result == .credited(packID: "starter", creditsAdded: 30, balance: 45))
            let bought = harness.session.allTransactions().filter { $0.productIdentifier == Self.starterProductID }
            let transaction = try #require(bought.first)
            #expect(bought.count == 1)
            let posted = CreditsGatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate")
            let request = try #require(posted.first)
            #expect(posted.count == 1)
            let body = try request.json()
            #expect(body["pack_id"] == "starter")
            #expect(body["product_id"] == Self.starterProductID)
            #expect(body["purchase_token"] == String(transaction.identifier))
            #expect(body["platform"] == "ios")
            let signed = try SignedTransactionPayload(jws: try #require(body["signed_transaction"]))
            #expect(signed.transactionId == String(transaction.identifier))
            #expect(signed.productId == Self.starterProductID)
            #expect(signed.appAccountToken?.uppercased() == StubIdentity.midgarID)
            #expect(request.header("X-App-ID") == "pay-day")
            #expect(request.header("Authorization") == "Bearer " + Self.legacyKey)
            #expect(request.header("X-Midgar-Token") == StubIdentity.accessToken)
            #expect(await eventually { harness.model.balance == 45 })
            #expect(await harness.credits.unconfirmedPurchases == 0)
            observing.cancel()
            await harness.stop()
        }

        @Test func aCreditPendingAnswerKeepsTheReceiptAndALaterRefreshCreditsIt() async throws {
            let harness = try makeHarness()
            CreditsGatewayStub.setBalance(15)
            CreditsGatewayStub.setValidate([.error(status: 409, code: "credit_pending", message: "The credit is on its way.")])

            let result = try await harness.credits.buy("starter")

            #expect(result == .creditPending(packID: "starter", credits: 30))
            #expect(await harness.credits.unconfirmedPurchases == 1)
            let validations = CreditsGatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate")
            let transactionIDs = try Set(validations.map { try $0.json()["purchase_token"] })
            #expect(validations.count == 4)
            #expect(transactionIDs.count == 1)
            let kept = try Data(contentsOf: harness.directory.appendingPathComponent("credits-pay-day.json"))
            #expect(String(decoding: kept, as: UTF8.self).contains(Self.starterProductID))

            CreditsGatewayStub.setBalance(45)
            CreditsGatewayStub.setValidate([.credited(added: 30, newBalance: 45)])
            let balance = try await harness.credits.refresh()

            #expect(balance.credits == 45)
            #expect(await harness.credits.unconfirmedPurchases == 0)
            let retried = CreditsGatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate")
            #expect(retried.count == 5)
            #expect(try Set(retried.map { try $0.json()["purchase_token"] }) == transactionIDs)
            await harness.stop()
        }

        @Test func aCancelledPurchaseCreditsNothingAndPostsNothing() async throws {
            let harness = try makeHarness(purchasing: CancellingStore())

            let result = try await harness.credits.buy("starter")

            #expect(result == .cancelled)
            #expect(CreditsGatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate").isEmpty)
            #expect(await harness.credits.unconfirmedPurchases == 0)
            await harness.stop()
        }

        @Test func aStoreKitFailureThrowsAndPostsNothing() async throws {
            let harness = try makeHarness()
            try await harness.session.setSimulatedError(.generic(.unknown), forAPI: .purchase)

            await #expect(throws: MidgarCreditsError.self) {
                _ = try await harness.credits.buy("starter")
            }

            #expect(CreditsGatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate").isEmpty)
            #expect(await harness.credits.unconfirmedPurchases == 0)
            #expect(harness.session.allTransactions().isEmpty)
            await harness.stop()
        }

        @Test func anUnknownPackIsRefusedBeforeStoreKitIsAsked() async throws {
            let harness = try makeHarness()

            await #expect(throws: MidgarCreditsError.self) {
                _ = try await harness.credits.buy("huge")
            }

            #expect(CreditsGatewayStub.requests(method: "POST", pathSuffix: "/v1/credits/purchase/revenuecat/validate").isEmpty)
            #expect(harness.session.allTransactions().isEmpty)
            await harness.stop()
        }
    }
}

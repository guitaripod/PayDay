import Foundation
import MidgarCredits
import os
import Testing
@testable import PayDay

/// The credit store's model against a scripted wallet: what each purchase result shows, and that nothing it shows is a
/// price or an amount the model decided.
@MainActor
@Suite(.serialized)
struct CreditStoreModelTests {
    private struct Harness {
        let wallet: ScriptedWallet
        let model: PayDayCreditStoreModel
        let failures: FailureLog
    }

    private struct FailureLog: Sendable {
        private let stored = OSAllocatedUnfairLock(initialState: [String]())

        var errors: [String] {
            stored.withLock { $0 }
        }

        func record(_ error: any Error) {
            stored.withLock { $0.append(String(describing: error)) }
        }
    }

    private func makeHarness(
        credits: Int = 12,
        shortfall: Int? = nil,
        restore: @escaping @Sendable () async throws -> Void = {}
    ) async -> Harness {
        let wallet = ScriptedWallet(credits: credits)
        await wallet.set(offers: scriptedOffers())
        let failures = FailureLog()
        let model = PayDayCreditStoreModel(
            source: wallet, shortfall: shortfall, restorePurchases: restore, purchaseFailed: { failures.record($0) })
        return Harness(wallet: wallet, model: model, failures: failures)
    }

    @Test func theStoreOpensWithTheBalanceAndTheFourPacks() async {
        let harness = await makeHarness(credits: 12)

        await harness.model.load()

        #expect(harness.model.phase == .ready)
        #expect(harness.model.balance == 12)
        #expect(harness.model.offers.map(\.pack.id) == ["starter", "regular", "propack", "business"])
    }

    @Test func aShortfallOpensTheStoreWithThatShortfallAndNonsenseIsIgnored() async {
        #expect(await makeHarness(shortfall: 18).model.shortfall == 18)
        #expect(await makeHarness(shortfall: 0).model.shortfall == nil)
        #expect(await makeHarness(shortfall: -4).model.shortfall == nil)
        #expect(await makeHarness(shortfall: nil).model.shortfall == nil)
    }

    @Test func noPacksFromTheAppStoreShowsThePacksAsUnavailableAndTryAgainLoadsThemAgain() async {
        let harness = await makeHarness()
        await harness.wallet.set(offers: [])
        await harness.model.load()
        #expect(harness.model.phase == .unavailable)

        await harness.wallet.set(offers: scriptedOffers())
        await harness.model.load()

        #expect(harness.model.phase == .ready)
    }

    @Test func aCreditedPurchaseTakesTheNewBalanceAndClosesTheStore() async throws {
        let harness = await makeHarness()
        await harness.model.load()
        let offer = try #require(harness.model.offers.first)
        await harness.wallet.set(purchase: .success(.credited(packID: "starter", creditsAdded: 30, balance: 42)))

        let outcome = await harness.model.buy(offer)

        #expect(outcome == .credited)
        #expect(harness.model.balance == 42)
        #expect(harness.model.notice == nil)
        #expect(await harness.wallet.bought == ["starter"])
        #expect(harness.model.buyingPackID == nil)
    }

    @Test func aPendingCreditShowsTheConfirmingRowAndTheStoreStaysOpen() async throws {
        let harness = await makeHarness()
        await harness.model.load()
        let offer = try #require(harness.model.offers.first)
        await harness.wallet.set(purchase: .success(.creditPending(packID: "starter", credits: 30)), unconfirmed: 1)

        let outcome = await harness.model.buy(offer)

        #expect(outcome == .stays)
        #expect(harness.model.confirming == 1)
        #expect(harness.model.notice == nil)

        let following = Task { await harness.model.observe() }
        await harness.wallet.set(purchase: .success(.cancelled), unconfirmed: 0)
        await harness.wallet.emit(.purchaseCredited(packID: "starter", creditsAdded: 30))
        #expect(await eventually { harness.model.confirming == 0 })
        following.cancel()
    }

    @Test func anApprovalThatIsPendingSaysTheCreditsArriveWhenItIsApproved() async throws {
        let harness = await makeHealthyHarness()
        let offer = try #require(harness.model.offers.first)
        await harness.wallet.set(purchase: .success(.awaitingApproval))

        let outcome = await harness.model.buy(offer)

        #expect(outcome == .stays)
        #expect(harness.model.notice == .awaitingApproval)
    }

    @Test func aCancelShowsNothing() async throws {
        let harness = await makeHealthyHarness()
        let offer = try #require(harness.model.offers.first)
        await harness.wallet.set(purchase: .success(.cancelled))

        let outcome = await harness.model.buy(offer)

        #expect(outcome == .stays)
        #expect(harness.model.notice == nil)
        #expect(harness.failures.errors.isEmpty)
    }

    @Test func aFailureIsOneSentenceAndIsRecorded() async throws {
        let harness = await makeHealthyHarness()
        let offer = try #require(harness.model.offers.first)
        await harness.wallet.set(purchase: .failure(MidgarCreditsError.offline))

        let outcome = await harness.model.buy(offer)

        #expect(outcome == .stays)
        #expect(harness.model.notice == .failure(PayDayCreditStoreModel.message(for: MidgarCreditsError.offline)))
        #expect(harness.failures.errors.count == 1)
        #expect(harness.model.buyingPackID == nil)
    }

    @Test func everyFailureMapsToTheSentenceItsCauseDeserves() {
        let generic = PayDayCreditStoreModel.message(for: MidgarCreditsError.invalidResponse)
        let sentences = [
            PayDayCreditStoreModel.message(for: MidgarCreditsError.offline),
            PayDayCreditStoreModel.message(for: MidgarCreditsError.walletUnavailable),
            PayDayCreditStoreModel.message(for: MidgarCreditsError.unauthorized),
            PayDayCreditStoreModel.message(for: MidgarCreditsError.rateLimited(retryAfter: nil)),
            PayDayCreditStoreModel.message(for: MidgarCreditsError.purchaseRejected(message: "refunded")),
            PayDayCreditStoreModel.message(for: MidgarCreditsError.notConfigured(.noPacks)),
            generic,
        ]
        #expect(Set(sentences).count == sentences.count)
        #expect(PayDayCreditStoreModel.message(for: MidgarCreditsError.insufficientCredits(balance: 3)) == generic)
        #expect(PayDayCreditStoreModel.message(for: URLError(.badURL)) == generic)
    }

    @Test func aRestoreRunsTheAppStoreSyncThenReadsTheBalanceAgain() async {
        let restored = RestoreLog()
        let harness = await makeHarness(credits: 12, restore: { await restored.count() })
        await harness.model.load()
        await harness.wallet.set(credits: 40)

        await harness.model.restore()

        #expect(await restored.value == 1)
        #expect(harness.model.balance == 40)
        #expect(!harness.model.isRestoring)
        #expect(harness.model.notice == nil)
    }

    @Test func aFailedRestoreIsASentence() async {
        let harness = await makeHarness(restore: { throw MidgarCreditsError.offline })
        await harness.model.load()

        await harness.model.restore()

        #expect(harness.model.notice == .failure(PayDayCreditStoreModel.message(for: MidgarCreditsError.offline)))
        #expect(!harness.model.isRestoring)
    }

    private func makeHealthyHarness() async -> Harness {
        let harness = await makeHarness()
        await harness.model.load()
        return harness
    }

    private actor RestoreLog {
        private(set) var value = 0

        func count() {
            value += 1
        }
    }
}

import Combine
import Foundation
import MidgarCredits
import Testing
@testable import PayDay

/// The balance model, which needs neither StoreKit nor the gateway.
@MainActor
@Suite(.serialized)
struct CreditsModelTests {
    @Test func theBalanceIsReadAtStartAndFollowsTheWalletsEvents() async {
        let wallet = ScriptedWallet(credits: 15)
        let model = CreditsModel(source: wallet)
        let following = Task { await model.start() }
        #expect(await eventually { model.balance == 15 })

        await wallet.emit(.balanceChanged(MidgarCreditsBalance(credits: 45, updatedAt: Date())))
        #expect(await eventually { model.balance == 45 })

        await wallet.set(credits: 155)
        await wallet.emit(.purchaseCredited(packID: "regular", creditsAdded: 110))
        #expect(await eventually { model.balance == 155 })
        following.cancel()
    }

    @Test func aFailedReadKeepsTheLastBalanceAndReturnsNil() async {
        let wallet = ScriptedWallet(credits: 12)
        let model = CreditsModel(source: wallet)
        #expect(await model.refresh() == 12)

        await wallet.set(credits: 99, failing: true)
        let failed = await model.refresh()

        #expect(failed == nil)
        #expect(model.balance == 12)
    }

    @Test func aReadThatIsAlreadyRunningIsJoinedNotRepeated() async {
        let wallet = ScriptedWallet(credits: 8)
        let model = CreditsModel(source: wallet)

        async let first = model.refresh()
        async let second = model.refresh()
        let balances = await [first, second]

        #expect(balances == [8, 8])
        #expect(await wallet.reads == 1)
        #expect(await model.refresh() == 8)
        #expect(await wallet.reads == 2)
    }

    @Test func theChangesPublisherSendsOnlyWhenTheBalanceChanged() async {
        let wallet = ScriptedWallet(credits: 6)
        let model = CreditsModel(source: wallet)
        var seen: [Int] = []
        let subscription = model.balanceChanges.sink { seen.append($0) }

        await model.refresh()
        await model.refresh()
        await wallet.set(credits: 2)
        await model.refresh()
        model.forget()

        #expect(seen == [6, 2, 0])
        subscription.cancel()
    }

    @Test func theLowBalanceThresholdStaysTenAndAnEmptyBalanceIsEmpty() async {
        #expect(CreditsModel.lowBalanceThreshold == 10)
        let model = CreditsModel(source: ScriptedWallet(credits: 9))
        #expect(model.isEmpty)
        await model.refresh()
        #expect(model.isLow)
        #expect(!model.isEmpty)
    }

    @Test func aDeletedAccountsBalanceIsForgotten() async {
        let model = CreditsModel(source: ScriptedWallet(credits: 30))
        await model.refresh()

        model.forget()

        #expect(model.balance == 0)
    }

    @Test func aModelWithoutAWalletStaysAtZeroAndReadsNothing() async {
        let model = CreditsModel(source: nil)

        let read = await model.refresh()

        #expect(read == nil)
        #expect(model.balance == 0)
        #expect(model.source == nil)
    }

    @Test func aPeppolSendNeedsThirtyCreditsAndTheShortfallIsWhatIsMissing() {
        #expect(CreditsModel.peppolSendCost == 30)
        #expect(CreditsModel.shortfall(cost: 30, balance: 12) == 18)
        #expect(CreditsModel.shortfall(cost: 30, balance: 0) == 30)
        #expect(CreditsModel.shortfall(cost: 30, balance: 30) == nil)
        #expect(CreditsModel.shortfall(cost: 30, balance: 45) == nil)
    }
}

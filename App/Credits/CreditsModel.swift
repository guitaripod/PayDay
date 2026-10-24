import Combine
import Foundation
import MidgarCore
import MidgarCredits
import MidgarCreditsUI
import Observation

/// The balance of the wallet for the screens: Settings shows it, the editor and the Peppol send decide from it whether
/// the person can afford the action, and the credit store is built on its source. It is read at launch, when the app
/// comes to the foreground, after every AI call and Peppol send and after a purchase, and it follows what
/// ``MidgarCredits/events()`` reports, so a purchase made in the credit store reaches every screen without anyone telling
/// them. UIKit screens bind to ``balanceChanges``, which sends only when the balance actually changed.
///
/// The source is nil where the app reaches no Midgar service (a test host), and the balance then stays 0.
@MainActor @Observable
final class CreditsModel {
    /// A balance below this counts as low.
    nonisolated static let lowBalanceThreshold = 10

    /// The model of the running app.
    static let shared = live()

    @ObservationIgnored let source: (any MidgarCreditStoreSource)?
    @ObservationIgnored let balanceChanges = PassthroughSubject<Int, Never>()
    @ObservationIgnored private var reading: Task<Int?, Never>?

    private(set) var balance = 0

    init(source: (any MidgarCreditStoreSource)?) {
        self.source = source
    }

    /// The model of the running app: the Midgar wallet, a fixed demo wallet in a DEBUG demo capture, or no wallet in a
    /// test host.
    private static func live() -> CreditsModel {
        #if DEBUG
        if DemoWorld.isActive {
            return CreditsModel(source: DemoCreditsSource())
        }
        #endif
        return CreditsModel(source: PayDayMidgar.shared.credits)
    }

    /// What a Peppol send costs, charged by mako on an accepted transmission.
    nonisolated static let peppolSendCost = 30

    /// How many more credits an action of `cost` credits needs, or nil when `balance` already covers it.
    nonisolated static func shortfall(cost: Int, balance: Int) -> Int? {
        cost > balance ? cost - balance : nil
    }

    var isLow: Bool {
        balance < Self.lowBalanceThreshold
    }

    var isEmpty: Bool {
        balance <= 0
    }

    /// Reads the balance, then follows the wallet's events until the stream ends. Run it for the life of the app.
    func start() async {
        await refresh()
        await observe()
    }

    /// Drops the balance of an account that was deleted, so no screen shows credits the wallet no longer holds.
    func forget() {
        apply(0)
    }

    /// Reads the balance from the wallet and returns it, or nil when there is no wallet or the read failed, which keeps
    /// the last balance known. A read that is already running is joined instead of repeated.
    @discardableResult
    func refresh() async -> Int? {
        if let reading {
            return await reading.value
        }
        guard source != nil else {
            return nil
        }
        let task = Task { await read() }
        reading = task
        let balance = await task.value
        reading = nil
        return balance
    }

    func handle(_ event: MidgarCreditsEvent) async {
        switch event {
        case .balanceChanged(let changed):
            apply(changed.credits)
        case .purchaseCredited:
            if let known = await source?.balance {
                apply(known.credits)
            }
        }
    }

    private func read() async -> Int? {
        do {
            guard let read = try await source?.refresh() else {
                return nil
            }
            apply(read.credits)
            return read.credits
        } catch {
            MidgarLog.notice("credits balance read failed: \(error)", category: .credits)
            return nil
        }
    }

    private func observe() async {
        guard let source else {
            return
        }
        for await event in await source.events() {
            await handle(event)
        }
    }

    private func apply(_ credits: Int) {
        guard credits != balance else {
            return
        }
        balance = credits
        balanceChanges.send(credits)
    }
}

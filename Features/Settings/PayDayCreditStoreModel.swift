import Foundation
import MidgarCore
import MidgarCredits
import MidgarCreditsUI
import Observation

/// The state of ``PayDayCreditStoreView``: the balance, the packs, the purchase or restore in progress, the purchases
/// still being confirmed and the message about the last result. The view only draws it. It buys through the wallet, so
/// every purchase carries the Midgar ID and is credited by mako; what it adds is the sentence for each outcome. A
/// credited purchase closes the store, as it always did.
@MainActor @Observable
final class PayDayCreditStoreModel {
    enum Phase: Equatable {
        case loading
        case ready
        case unavailable
    }

    enum Notice: Equatable {
        case awaitingApproval
        case failure(String)
    }

    /// What buying a pack came to, for the view: whether the store should close.
    enum Outcome: Equatable {
        case credited
        case stays
    }

    @ObservationIgnored private let source: any MidgarCreditStoreSource
    @ObservationIgnored private let restorePurchases: @Sendable () async throws -> Void
    @ObservationIgnored private let purchaseFailed: @Sendable (any Error) -> Void
    let shortfall: Int?

    private(set) var phase = Phase.loading
    private(set) var balance: Int?
    private(set) var offers: [MidgarCreditsOffer] = []
    private(set) var buyingPackID: String?
    private(set) var isRestoring = false
    private(set) var confirming = 0
    private(set) var notice: Notice?

    init(
        source: any MidgarCreditStoreSource,
        shortfall: Int?,
        restorePurchases: @escaping @Sendable () async throws -> Void,
        purchaseFailed: @escaping @Sendable (any Error) -> Void = PayDayCreditStoreModel.recordPurchaseFailure
    ) {
        self.source = source
        self.shortfall = shortfall.flatMap { $0 > 0 ? $0 : nil }
        self.restorePurchases = restorePurchases
        self.purchaseFailed = purchaseFailed
    }

    var isWorking: Bool {
        buyingPackID != nil || isRestoring
    }

    /// Reads the balance and the packs together, then picks up the purchases an earlier launch left unconfirmed. A failure
    /// of one does not hide the other.
    func load() async {
        let source = source
        async let refreshed = Self.attempt { try await source.refresh() }
        async let loaded = Self.attempt { try await source.offers() }
        let (balanceResult, offersResult) = await (refreshed, loaded)
        guard !Task.isCancelled else {
            return
        }
        switch balanceResult {
        case .success(let read):
            balance = read.credits
        case .failure:
            balance = await source.balance?.credits ?? balance
        }
        if case .success(let found) = offersResult {
            offers = found
        }
        phase = offers.isEmpty ? .unavailable : .ready
        confirming = await source.unconfirmedPurchases
    }

    /// Follows what the wallet reports until the stream ends. Run it for as long as the view is on screen.
    func observe() async {
        for await event in await source.events() {
            switch event {
            case .balanceChanged(let changed):
                balance = changed.credits
            case .purchaseCredited:
                confirming = await source.unconfirmedPurchases
            }
        }
    }

    /// Buys the pack and records what came of it. Cancelling does nothing visible; the other results become the balance, a
    /// confirming row or a message.
    func buy(_ offer: MidgarCreditsOffer) async -> Outcome {
        guard !isWorking else {
            return .stays
        }
        buyingPackID = offer.pack.id
        notice = nil
        defer { buyingPackID = nil }
        do {
            switch try await source.buy(offer.pack.id) {
            case .credited(_, _, let newBalance):
                balance = newBalance
                return .credited
            case .creditPending:
                confirming = await source.unconfirmedPurchases
            case .awaitingApproval:
                notice = .awaitingApproval
            case .cancelled:
                break
            }
        } catch is CancellationError {
            return .stays
        } catch {
            purchaseFailed(error)
            notice = .failure(Self.message(for: error))
        }
        return .stays
    }

    /// Asks the App Store to sync, then reads the balance again, which also sends any purchase still waiting for its credit.
    func restore() async {
        guard !isWorking else {
            return
        }
        isRestoring = true
        notice = nil
        defer { isRestoring = false }
        do {
            try await restorePurchases()
            if let read = try? await source.refresh() {
                balance = read.credits
            }
            confirming = await source.unconfirmedPurchases
        } catch is CancellationError {
            return
        } catch {
            notice = .failure(Self.message(for: error))
        }
    }

    /// The one short sentence for a failure a person can act on.
    static func message(for error: any Error) -> String {
        guard let credits = error as? MidgarCreditsError else {
            return String(localized: "The purchase could not be completed. Please try again.")
        }
        switch credits {
        case .offline:
            return String(localized: "You are offline. Check your connection and try again.")
        case .walletUnavailable:
            return String(localized: "Credits are unavailable right now. Nothing was charged.")
        case .unauthorized, .identityUnavailable:
            return String(localized: "Your session has expired. Sign in and try again.")
        case .rateLimited:
            return String(localized: "Too many requests. Try again in a moment.")
        case .purchaseRejected:
            return String(localized: "The purchase could not be verified. If you were charged, contact support.")
        case .notConfigured:
            return String(localized: "Credit packs are not available right now.")
        case .insufficientCredits, .store, .server, .invalidResponse:
            return String(localized: "The purchase could not be completed. Please try again.")
        @unknown default:
            return String(localized: "The purchase could not be completed. Please try again.")
        }
    }

    /// What the running app does with a failed purchase: writes it to the file log and holds the review prompt back.
    nonisolated static func recordPurchaseFailure(_ error: any Error) {
        MidgarLog.error("credits error: \(error.localizedDescription)", category: .credits)
        ReviewPrompt.notePurchaseFailure()
    }

    nonisolated private static func attempt<Value: Sendable>(
        _ work: @Sendable () async throws -> Value
    ) async -> Result<Value, any Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}

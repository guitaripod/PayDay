#if DEBUG
import Foundation
import MidgarCommerce
import MidgarCredits
import MidgarCreditsUI

/// The wallet of a demo capture: a fixed balance, the four packs at their store prices and no network. A simulator can
/// never pass the App Attest check mako's identity endpoint requires, so the live balance would read 0 there. Buying
/// does nothing, so a capture can never charge anything.
struct DemoCreditsSource: MidgarCreditStoreSource {
    static let balance = 120

    var balance: MidgarCreditsBalance? {
        get async { Self.fixedBalance }
    }

    var unconfirmedPurchases: Int {
        get async { 0 }
    }

    func refresh() async throws -> MidgarCreditsBalance {
        Self.fixedBalance
    }

    func offers() async throws -> [MidgarCreditsOffer] {
        PayDayPacks.all.compactMap { pack in
            Self.storeListing[pack.id].map { price in
                MidgarCreditsOffer(
                    pack: pack,
                    product: StoreProduct(
                        id: pack.productID, displayName: PayDayPacks.name(of: pack), description: "", displayPrice: price)
                )
            }
        }
    }

    func buy(_ packID: String) async throws -> MidgarCreditsPurchaseResult {
        .cancelled
    }

    func events() async -> AsyncStream<MidgarCreditsEvent> {
        AsyncStream { _ in }
    }

    private static let storeListing = [
        PayDayPacks.starter.id: "$2.99",
        PayDayPacks.regular.id: "$9.99",
        PayDayPacks.propack.id: "$24.99",
        PayDayPacks.business.id: "$49.99",
    ]

    private static var fixedBalance: MidgarCreditsBalance {
        MidgarCreditsBalance(credits: balance, updatedAt: Date())
    }
}
#endif

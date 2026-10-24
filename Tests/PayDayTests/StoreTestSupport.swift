import Foundation
import MidgarCommerce
import MidgarCredits
import MidgarCreditsUI
import UIKit
@testable import PayDay

/// The store with every purchase confirmed in the host app's window scene, as StoreKit needs inside a test host: a
/// scene-less purchase there never completes, because StoreKit finds no window to confirm in. Everything else is the
/// store itself, and MidgarCredits and ProAccess sell through this exactly as they sell through the store.
struct SceneAnchoredStore: MidgarCreditsPurchasing, ProStoring {
    let store: MidgarStore

    func products() async throws -> [StoreProduct] {
        try await store.products()
    }

    func purchaseReceipt(_ productID: String) async throws -> MidgarReceiptResult {
        try await receipt(productID)
    }

    func purchase(_ productID: String) async throws -> MidgarPurchaseResult {
        switch try await receipt(productID) {
        case .purchased: return .purchased
        case .pending: return .pending
        case .cancelled: return .cancelled
        }
    }

    func isEntitled(to name: String) async -> Bool {
        await store.isEntitled(to: name)
    }

    func restore() async throws {
        try await store.restore()
    }

    func refresh() async {
        await store.refresh()
    }

    func events() async -> AsyncStream<MidgarStoreEvent> {
        await store.events()
    }

    @MainActor
    private func receipt(_ productID: String) async throws -> MidgarReceiptResult {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            throw MidgarStoreError.unsupportedPlatform
        }
        return try await store.purchaseReceipt(productID, confirmIn: scene)
    }
}

/// The customer dismissing the purchase sheet. StoreKitTest cannot script that (a simulated `userCancelled` error
/// surfaces as a StoreKit failure, not as the `userCancelled` result), so the store answers `.cancelled` itself, which is
/// what MidgarStore returns for the real result. Nothing is bought and StoreKit is not asked.
struct CancellingStore: MidgarCreditsPurchasing, ProStoring {
    func products() async throws -> [StoreProduct] { [] }
    func purchaseReceipt(_ productID: String) async throws -> MidgarReceiptResult { .cancelled }
    func purchase(_ productID: String) async throws -> MidgarPurchaseResult { .cancelled }
    func isEntitled(to name: String) async -> Bool { false }
    func restore() async throws {}
    func refresh() async {}
    func events() async -> AsyncStream<MidgarStoreEvent> { AsyncStream { _ in } }
}

/// A wallet the test controls: what a read answers, how many reads there were, what a purchase answers and the stream of
/// events the models follow.
actor ScriptedWallet: MidgarCreditStoreSource {
    struct Offline: Error {}

    private var credits: Int
    private var fails = false
    private var offerList: [MidgarCreditsOffer] = []
    private var purchase: Result<MidgarCreditsPurchaseResult, any Error> = .success(.cancelled)
    private var unconfirmed = 0
    private(set) var reads = 0
    private(set) var bought: [String] = []
    private let stream: AsyncStream<MidgarCreditsEvent>
    private let continuation: AsyncStream<MidgarCreditsEvent>.Continuation

    init(credits: Int) {
        self.credits = credits
        (stream, continuation) = AsyncStream.makeStream()
    }

    var balance: MidgarCreditsBalance? { balanceValue }

    var unconfirmedPurchases: Int { unconfirmed }

    func set(credits: Int, failing: Bool = false) {
        self.credits = credits
        fails = failing
    }

    func set(offers: [MidgarCreditsOffer]) {
        offerList = offers
    }

    func set(purchase: Result<MidgarCreditsPurchaseResult, any Error>, unconfirmed: Int = 0) {
        self.purchase = purchase
        self.unconfirmed = unconfirmed
    }

    func emit(_ event: MidgarCreditsEvent) {
        continuation.yield(event)
    }

    func refresh() async throws -> MidgarCreditsBalance {
        reads += 1
        try? await Task.sleep(for: .milliseconds(20))
        if fails {
            throw Offline()
        }
        return balanceValue
    }

    func offers() async throws -> [MidgarCreditsOffer] { offerList }

    func buy(_ packID: String) async throws -> MidgarCreditsPurchaseResult {
        bought.append(packID)
        return try purchase.get()
    }

    func events() async -> AsyncStream<MidgarCreditsEvent> { stream }

    private var balanceValue: MidgarCreditsBalance {
        MidgarCreditsBalance(credits: credits, updatedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }
}

/// The offers the app's four packs make at the prices of `Products.storekit`.
func scriptedOffers() -> [MidgarCreditsOffer] {
    let prices = ["$2.99", "$9.99", "$24.99", "$49.99"]
    return zip(PayDayPacks.all, prices).map { pack, price in
        MidgarCreditsOffer(
            pack: pack,
            product: StoreProduct(
                id: pack.productID, displayName: PayDayPacks.name(of: pack), description: "", displayPrice: price))
    }
}

/// Polls until a condition holds or the timeout passes, for outcomes that arrive from other tasks.
@MainActor
func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}

/// The claims of a signed transaction the validate request carries, read from the JWS payload.
struct SignedTransactionPayload: Decodable {
    let transactionId: String
    let productId: String
    let appAccountToken: String?

    init(jws: String) throws {
        let parts = jws.split(separator: ".")
        guard parts.count == 3 else {
            throw URLError(.cannotParseResponse)
        }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else {
            throw URLError(.cannotDecodeContentData)
        }
        self = try JSONDecoder().decode(SignedTransactionPayload.self, from: data)
    }
}

/// The parts of a StoreKit configuration file the product checks read.
struct StoreKitFile: Decodable {
    struct Item: Decodable {
        let productID: String
        let displayPrice: String
        let referenceName: String
        let type: String?
    }

    struct Group: Decodable {
        let name: String
        let subscriptions: [Item]
    }

    let products: [Item]
    let subscriptionGroups: [Group]

    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Products.storekit")

    static func load() throws -> StoreKitFile {
        try JSONDecoder().decode(StoreKitFile.self, from: Data(contentsOf: url))
    }
}

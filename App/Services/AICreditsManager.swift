import Foundation
import AICreditsCore
import AICreditsUI
import MidgarCore

/// Owns the AICredits client, which here runs the AI calls (metered by mako against the Midgar ID's wallet) and holds the
/// old per-app account behind the mako api key: the key that authenticates Pay Day's worker, and the account Sign in
/// with Apple links. Calls go to mako behind the gateway and carry the Midgar token next to the api key. Its purchase
/// provider cannot buy, because the credit packs and the Pro plans are sold by MidgarStore.
final class AICreditsManager: Sendable {
    static let shared = AICreditsManager()

    /// The store the credit store's Sign in with Apple row reads and writes: it holds the account's identity and
    /// reports a failed link. It buys nothing and shows no balance.
    @MainActor static let accountLink = AICreditsStore(client: AICreditsManager.shared.client)

    let client: AICreditsClient
    let baseURL = PayDayMidgar.intelligenceURL
    private let appID = PayDayMidgar.tenantID

    private init() {
        let config = AICreditsConfig(
            baseURL: baseURL, appID: appID, lowBalanceThreshold: CreditsModel.lowBalanceThreshold,
            additionalHeaders: { await PayDayMidgar.shared.midgarTokenHeaders() })
        client = AICreditsClient(config: config, purchaseProvider: HostManagedPurchaseProvider())
    }

    /// The api key of the old per-app account, which MidgarCredits sends as its legacy key so mako links the balance
    /// from before the move to the Midgar ID's wallet. The key lives in the keychain; a device that has none yet gets
    /// its account registered here, the same one the first AI call would register. Nil when that fails.
    func legacyAPIKey() async -> String? {
        try? await client.bootstrap().apiKey
    }
}

/// The purchase provider the AICredits client needs but never uses: it sells nothing, and every purchase attempt fails.
private struct HostManagedPurchaseProvider: PurchaseProvider {
    func configure(appUserID: String) async {}
    func availablePackages() async throws -> [StorePackage] { [] }
    func purchase(packageID: String) async throws -> PurchaseReceipt {
        throw AICreditsError.purchaseFailed("Purchases are handled by the host app.")
    }
    func restore() async throws -> [RestoredEntitlement] { [] }
    func alias(to newAppUserID: String) async {}
}

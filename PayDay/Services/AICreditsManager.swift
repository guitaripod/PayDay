import Foundation
import AICreditsCore
import AICreditsRevenueCat
import AICreditsUI

/// Wires the shared mako AI-credits backend through the AICredits package. The
/// `pro` entitlement (subscription) gates compliant e-invoicing; consumable
/// credit packs meter per-Peppol-send cost and AI actions.
final class AICreditsManager: Sendable {
    static let shared = AICreditsManager()

    @MainActor static let store = AICreditsStore(
        client: AICreditsManager.shared.client, lowBalanceThreshold: 10)

    let client: AICreditsClient
    let baseURL = Secrets.makoBaseURL
    private let appID = "payday"
    private let revenueCatPublicKey = Secrets.revenueCatPublicKey

    private init() {
        let config = AICreditsConfig(baseURL: baseURL, appID: appID, lowBalanceThreshold: 10)
        client = AICreditsClient(
            config: config,
            purchaseProvider: RevenueCatPurchaseProvider(apiKey: revenueCatPublicKey))
    }
}

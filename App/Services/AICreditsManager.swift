import Foundation
import AICreditsCore
import AICreditsRevenueCat
import AICreditsUI
import MidgarCore

/// Wires the shared mako AI-credits backend through the AICredits package. The
/// `pro` entitlement (subscription) gates compliant e-invoicing; consumable
/// credit packs meter per-Peppol-send cost and AI actions. Calls go to mako behind the
/// gateway and carry the Midgar token next to the api key.
final class AICreditsManager: Sendable {
    static let shared = AICreditsManager()

    @MainActor static let store = AICreditsStore(
        client: AICreditsManager.shared.client, lowBalanceThreshold: 10)

    let client: AICreditsClient
    let baseURL = PayDayMidgar.intelligenceURL
    private let appID = PayDayMidgar.tenantID
    private let revenueCatPublicKey = Secrets.revenueCatPublicKey

    private init() {
        let config = AICreditsConfig(
            baseURL: baseURL, appID: appID, lowBalanceThreshold: 10, premiumEntitlement: "pro",
            additionalHeaders: { await PayDayMidgar.shared.midgarTokenHeaders() })
        client = AICreditsClient(
            config: config,
            purchaseProvider: RevenueCatPurchaseProvider(apiKey: revenueCatPublicKey))
    }

    /// Reports the Apple Ads install attribution once, in the background, so a
    /// paid install can later be joined to whether that user subscribed. The
    /// token is exchanged with Apple server-side, is never logged, and campaign
    /// identifiers stay on the backend — only the verdict is traced here.
    func reportAdAttribution() {
        client.startAdAttributionReporting { result in
            MidgarLog.info("ad attribution \(result.logDescription)", category: .credits)
        }
    }
}

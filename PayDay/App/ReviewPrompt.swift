import StoreKit
import UIKit

/// Asks for an App Store rating only after the user has actually finished the
/// app's core job a few times, and at most once per app version.
///
/// Rating count is both a ranking input and the strongest conversion signal on
/// a product page — an app showing "5 ratings" and one showing "300" convert
/// very differently from the same impressions. Prompting before any value has
/// landed buys one-star reviews instead, so the counter only advances on a
/// document the user actually delivered.
@MainActor
enum ReviewPrompt {
    private static let deliveriesBeforeAsking = 2

    /// Call after an invoice reaches its recipient — a completed share sheet or
    /// an accepted Peppol transmission.
    static func recordDelivery(from viewController: UIViewController) {
        AppSettings.deliveredDocumentCount += 1
        askIfEarned(from: viewController)
    }

    private static func askIfEarned(from viewController: UIViewController) {
        let delivered = AppSettings.deliveredDocumentCount
        guard delivered >= deliveriesBeforeAsking else { return }
        guard AppSettings.ratingPromptShownVersion != currentVersion else { return }
        guard let scene = viewController.view.window?.windowScene else { return }
        AppSettings.ratingPromptShownVersion = currentVersion
        AppLogger.shared.info("review prompt requested after \(delivered) deliveries", category: .app)
        AppStore.requestReview(in: scene)
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}

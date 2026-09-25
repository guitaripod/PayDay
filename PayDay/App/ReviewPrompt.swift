import PayDayKit
import StoreKit
import UIKit

/// Asks for an App Store rating after a real invoice goes out, and again
/// later if the first ask didn't come from an already-happy user — never
/// more than Apple's own cap of three prompts in any rolling year.
///
/// Rating count is both a ranking input and the strongest conversion signal on
/// a product page — an app showing "5 ratings" and one showing "300" convert
/// very differently from the same impressions. Prompting before any value has
/// landed buys one-star reviews instead, so the counter only advances on a
/// document the user actually delivered. The timing math itself lives in
/// `ReviewEligibility`, in PayDayKit, so it's testable without StoreKit.
@MainActor
enum ReviewPrompt {
    private static let askDelay: TimeInterval = 1.5

    /// Call after an invoice reaches its recipient — a completed share sheet or
    /// an accepted Peppol transmission.
    static func recordDelivery(from viewController: UIViewController) {
        AppSettings.migrateLegacyReviewStateIfNeeded()
        AppSettings.reviewSuccessCount += 1
        let successCount = AppSettings.reviewSuccessCount
        AppLogger.shared.info("review: recorded delivery #\(successCount)", category: .app)
        askIfEligible(from: viewController, successCount: successCount)
    }

    private static func askIfEligible(from viewController: UIViewController, successCount: Int) {
        let now = Date()
        let askDates = AppSettings.reviewAskDates
        let eligible = ReviewEligibility.shouldAsk(
            successCount: successCount,
            askDates: askDates,
            successCountAtLastAsk: AppSettings.reviewSuccessCountAtLastAsk,
            now: now)
        guard eligible else {
            AppLogger.shared.info("review: skipped (not eligible — \(successCount) deliveries, \(askDates.count) prior asks)", category: .app)
            return
        }
        guard let scene = viewController.view.window?.windowScene else {
            AppLogger.shared.info("review: skipped (no window scene)", category: .app)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + askDelay) { [weak viewController] in
            request(in: viewController, scene: scene, now: now, successCount: successCount, priorAskCount: askDates.count)
        }
    }

    /// Re-checks that nothing moved between the eligibility decision and the
    /// delayed ask: the view still on screen with nothing presented over it
    /// (no paywall, purchase sheet, alert, or error that appeared in the
    /// meantime), and the scene still the one the user is actively looking at.
    private static func request(
        in viewController: UIViewController?,
        scene: UIWindowScene,
        now: Date,
        successCount: Int,
        priorAskCount: Int
    ) {
        guard let viewController, viewController.viewIfLoaded?.window != nil else {
            AppLogger.shared.info("review: skipped (the originating screen left the window)", category: .app)
            return
        }
        guard viewController.presentedViewController == nil else {
            AppLogger.shared.info("review: skipped (something presented before the delay elapsed)", category: .app)
            return
        }
        guard scene.activationState == .foregroundActive else {
            AppLogger.shared.info("review: skipped (scene not foreground-active)", category: .app)
            return
        }
        AppSettings.reviewAskDates += [now]
        AppSettings.reviewSuccessCountAtLastAsk = successCount
        AppLogger.shared.info("review: asked (#\(priorAskCount + 1))", category: .app)
        AppStore.requestReview(in: scene)
    }
}

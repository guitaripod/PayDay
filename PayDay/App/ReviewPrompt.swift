import MidgarCommerce
import MidgarCore
import StoreKit
import UIKit

/// Asks for an App Store rating after a real invoice goes out. `MidgarReviewPolicy` decides whether an ask is due (the
/// shared Midgar rules: not in the first days or sessions, not within 120 days of the last ask or on the version that
/// asked, not within a week of a failed purchase); this type reports each delivery to it and, when it says yes, asks
/// StoreKit a beat later, once the success UI has landed and only while nothing else is covering the screen.
///
/// A rating count is both a ranking input and the strongest conversion signal on a product page. Prompting before any
/// value has landed buys one-star reviews instead, so the only positive moment reported is a document the user
/// actually delivered: a completed share sheet or an accepted Peppol transmission.
@MainActor
enum ReviewPrompt {
    static let askDelay: Duration = .milliseconds(1_500)

    /// Guards against a second delivery landing while the first ask is still delayed: without it, two deliveries
    /// within the same delay could each see themselves as due and both call StoreKit.
    private static var askPending = false

    nonisolated static let policy: MidgarReviewPolicy = {
        let storage = MidgarReviewFileStorage(appID: PayDayMidgar.appID)
        LegacyReviewState.migrate(from: .standard, into: storage)
        return MidgarReviewPolicy(storage: storage)
    }()

    /// Counts one session. Call it once per launch.
    nonisolated static func beginSession() {
        policy.beginSession()
    }

    /// Reports a purchase that failed, which holds the prompt back for a week.
    nonisolated static func notePurchaseFailure() {
        policy.notePurchaseFailure()
    }

    /// Call after an invoice reaches its recipient. Tallies the delivery with the policy and, if it allows an ask,
    /// asks for a rating a beat later. The scene is captured now, because by the time the ask runs the screen may be
    /// gone.
    static func recordDelivery(from viewController: UIViewController) {
        guard policy.noteSuccess() else {
            MidgarLog.info("review prompt skipped: \(policy.evaluate())", category: .app)
            return
        }
        guard let scene = viewController.view.window?.windowScene else {
            MidgarLog.info("review prompt skipped (no window scene)", category: .app)
            return
        }
        guard !askPending else {
            MidgarLog.info("review prompt skipped: an ask is already pending", category: .app)
            return
        }
        askPending = true
        Task { [weak viewController] in
            defer { askPending = false }
            try? await Task.sleep(for: askDelay)
            ask(in: scene, from: viewController)
        }
    }

    /// Re-checks that nothing moved between the policy's decision and the delayed ask: the view still on screen with
    /// nothing presented over it (no paywall, purchase sheet, alert, or error that appeared in the meantime), and the
    /// scene still the one the user is actively looking at.
    private static func ask(in scene: UIWindowScene, from viewController: UIViewController?) {
        guard let viewController, viewController.viewIfLoaded?.window != nil else {
            MidgarLog.info("review prompt skipped (the originating screen left the window)", category: .app)
            return
        }
        guard viewController.presentedViewController == nil else {
            MidgarLog.info("review prompt skipped (something presented before the delay elapsed)", category: .app)
            return
        }
        guard scene.activationState == .foregroundActive else {
            MidgarLog.info("review prompt skipped (scene not foreground-active)", category: .app)
            return
        }
        policy.notePrompted()
        MidgarLog.info("review prompt requested", category: .app)
        AppStore.requestReview(in: scene)
    }
}

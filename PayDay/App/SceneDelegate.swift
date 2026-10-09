import Combine
import UIKit
import PayDayKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var creditsObservers: Set<AnyCancellable> = []
    private var didReportAdAttribution = false

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        observeCreditsEvents()

        let window = UIWindow(windowScene: windowScene)
        window.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: AppSettings.appearance.rawValue) ?? .unspecified
        window.tintColor = DesignSystem.Color.accent
        window.rootViewController = Self.makeRoot()
        self.window = window
        window.makeKeyAndVisible()
        #if DEBUG
        if let demo = ProcessInfo.processInfo.environment["PAYDAY_DEMO"] {
            DemoRouting.settle(window.rootViewController, screen: demo)
        }
        #endif

        Task { await AICreditsManager.store.bootstrap() }
        reportAdAttributionOnce()
        AppLogger.shared.info("scene connected", category: .app)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        reportAdAttributionOnce()
    }

    /// Reports the install attribution once per launch, driven from scene
    /// connection rather than scene activation.
    ///
    /// It must not wait for `sceneDidBecomeActive`: on the only launch that can
    /// ever produce an attribution — the first one after an ad-driven install — a
    /// permission alert is typically on screen, and a presented system alert keeps
    /// the scene `inactive` until the user answers it. The AdServices token is
    /// short-lived, so deferring capture until then loses the install. Nothing
    /// here touches the launch critical path: the reporter returns immediately and
    /// does its work on a detached task.
    private func reportAdAttributionOnce() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PAYDAY_DEMO"] != nil { return }
        #endif
        guard !didReportAdAttribution else { return }
        didReportAdAttribution = true
        AICreditsManager.shared.reportAdAttribution()
    }

    private static func makeRoot() -> UIViewController {
        #if DEBUG
        if let demo = ProcessInfo.processInfo.environment["PAYDAY_DEMO"], let root = DemoRouting.root(for: demo) {
            return root
        }
        #endif
        if AppSettings.hasOnboarded {
            return RootViewController()
        }
        return OnboardingViewController.makeFlow { window in
            AppSettings.hasOnboarded = true
            window?.rootViewController = RootViewController()
        }
    }


    /// The AICredits package emits no logging of its own, so the store's
    /// published identity/error/balance transitions are the app's only trace of
    /// bootstrap, Apple-link, refresh, and purchase outcomes.
    private func observeCreditsEvents() {
        let store = AICreditsManager.store
        store.$identity
            .compactMap { $0 }
            .removeDuplicates()
            .sink { AppLogger.shared.info("credits identity \($0.kind.rawValue) \($0.userID.prefix(8))", category: .credits) }
            .store(in: &creditsObservers)
        store.$error
            .compactMap { $0 }
            .sink { AppLogger.shared.error("credits error: \($0.localizedDescription)", category: .credits) }
            .store(in: &creditsObservers)
        store.$balance
            .removeDuplicates()
            .dropFirst()
            .sink { AppLogger.shared.info("credits balance \($0)", category: .credits) }
            .store(in: &creditsObservers)
    }

}

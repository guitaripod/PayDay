import Combine
import UIKit
import PayDayCore
import MidgarCore

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let credits = CreditsModel.shared
    private var creditsObservers: Set<AnyCancellable> = []
    private var didReportAdAttribution = false

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        observeCreditsEvents()
        Task { await credits.start() }

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

        reportAdAttributionOnce()
        MidgarLog.info("scene connected", category: .app)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        reportAdAttributionOnce()
        Task { await credits.refresh() }
    }

    /// Reports the install attribution once per launch, driven from scene
    /// connection rather than scene activation.
    ///
    /// It must not wait for `sceneDidBecomeActive`: on the only launch that can
    /// ever produce an attribution — the first one after an ad-driven install — a
    /// permission alert is typically on screen, and a presented system alert keeps
    /// the scene `inactive` until the user answers it. The AdServices token is
    /// short-lived, so deferring capture until then loses the install. Nothing
    /// here touches the launch critical path: the wallet does the work on its own
    /// actor and remembers mako's verdict, so an install is settled once. A test
    /// host, a demo capture and a debug build have no wallet or say it is not a
    /// production launch, and report nothing.
    private func reportAdAttributionOnce() {
        guard !didReportAdAttribution, let wallet = PayDayMidgar.shared.credits else { return }
        didReportAdAttribution = true
        Task {
            let result = await wallet.reportAdAttributionOnce()
            MidgarLog.info("ad attribution \(result.logDescription)", category: .credits)
        }
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

    /// The balance transitions are the only app-visible trace of the wallet, so each change is written to the file log.
    private func observeCreditsEvents() {
        credits.balanceChanges
            .sink { MidgarLog.info("credits balance \($0)", category: .credits) }
            .store(in: &creditsObservers)
    }
}

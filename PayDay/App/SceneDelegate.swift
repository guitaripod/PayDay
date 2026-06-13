import Combine
import UIKit
import PayDayKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var creditsObservers: Set<AnyCancellable> = []

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

        Task { await AICreditsManager.store.bootstrap() }
        AppLogger.shared.info("scene connected", category: .app)
    }

    private static func makeRoot() -> UIViewController {
        #if DEBUG
        if let demo = ProcessInfo.processInfo.environment["PAYDAY_DEMO"], let root = demoRoot(demo) {
            return root
        }
        #endif
        if AppSettings.hasOnboarded {
            return RootViewController()
        }
        let onboarding = OnboardingViewController()
        onboarding.onFinish = { [weak onboarding] in
            AppSettings.hasOnboarded = true
            onboarding?.view.window?.rootViewController = RootViewController()
        }
        return onboarding
    }

    #if DEBUG
    /// Deterministic screen routing for App Store screenshot capture.
    /// `xcrun simctl launch <dev> com.guitaripod.payday` after
    /// `... --console` with `PAYDAY_DEMO=<screen>` in the environment.
    private static func demoRoot(_ screen: String) -> UIViewController? {
        AppSettings.hasOnboarded = true
        func nav(_ vc: UIViewController) -> UINavigationController {
            let n = UINavigationController(rootViewController: vc)
            n.navigationBar.prefersLargeTitles = true
            return n
        }
        switch screen {
        case "dashboard", "list", "clients":
            let tabs = RootViewController()
            tabs.selectedIndex = ["dashboard": 0, "list": 1, "clients": 2][screen] ?? 0
            return tabs
        case "editor":
            return nav(InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(existing: DemoData.sampleInvoice())))
        case "preview":
            return nav(InvoicePreviewViewController(invoice: DemoData.sampleInvoice(), demoForceCompliant: true))
        case "preview-ic":
            return nav(InvoicePreviewViewController(invoice: DemoData.sampleIntraCommunityInvoice(), demoForceCompliant: true))
        case "paywall":
            return nav(PaywallViewController())
        default:
            return nil
        }
    }
    #endif

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

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        warmUpLaunchServicesReceiptPath()
        _ = DatabaseManager.shared
        DemoSeeder.seedIfNeeded()
        AppLogger.shared.info("app launched", category: .app)
        return true
    }

    /// Pre-warms the LaunchServices XPC connection behind
    /// `Bundle.main.appStoreReceiptURL` on the main thread, before RevenueCat's
    /// background queue reads it during configuration (insurance against the
    /// iOS 26.5 launch race in purchases-ios#6886).
    private func warmUpLaunchServicesReceiptPath() {
        _ = Bundle.main.appStoreReceiptURL
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

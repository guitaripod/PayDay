import UIKit
import MidgarCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PayDayMidgar.configureLogging()
        PayDayMidgar.shared.start()
        ReviewPrompt.beginSession()
        _ = DatabaseManager.shared
        seedLocalData()
        MidgarLog.info("app launched", category: .app)
        return true
    }

    private func seedLocalData() {
        #if DEBUG
        if DemoWorld.isActive {
            DemoWorld.reseed()
            return
        }
        #endif
        DemoSeeder.seedIfNeeded()
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

import UIKit

/// The app's tab shell: Dashboard, Invoices, Clients, Settings. Each tab is a
/// navigation stack so detail/editor screens push naturally.
final class RootViewController: UITabBarController {
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        viewControllers = [
            wrap(DashboardViewController(), title: "Home", symbol: "house.fill"),
            wrap(InvoiceListViewController(kind: .invoice), title: "Invoices", symbol: "doc.text.fill"),
            wrap(ClientListViewController(), title: "Clients", symbol: "person.2.fill"),
            wrap(SettingsViewController(), title: "Settings", symbol: "gearshape.fill"),
        ]
    }

    private func wrap(_ vc: UIViewController, title: String, symbol: String) -> UINavigationController {
        vc.title = title
        vc.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), selectedImage: nil)
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }
}

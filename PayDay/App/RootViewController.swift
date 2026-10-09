import UIKit

/// The app's tab shell: Dashboard, Invoices, Clients, Settings. The list-shaped
/// tabs are list-and-detail splits that fold onto a plain navigation stack in a
/// narrow window; the dashboard is a navigation stack of its own.
final class RootViewController: UITabBarController {
    enum Tab: Int { case dashboard, invoices, clients, settings }

    let invoicesSplit = ListDetailSplitViewController(
        list: InvoiceListViewController(kind: .invoice), placeholderSymbol: "doc.text")
    let clientsSplit = ListDetailSplitViewController(
        list: ClientListViewController(), placeholderSymbol: "person.2")
    let settingsSplit = ListDetailSplitViewController(
        list: SettingsViewController(), placeholderSymbol: "gearshape")

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabBar.tintColor = DesignSystem.Color.accent
        viewControllers = [
            wrap(DashboardViewController(), title: String(localized: "Home"), symbol: "house.fill"),
            tabItem(invoicesSplit, title: String(localized: "Invoices"), symbol: "doc.text.fill"),
            tabItem(clientsSplit, title: String(localized: "Clients"), symbol: "person.2.fill"),
            tabItem(settingsSplit, title: String(localized: "Settings"), symbol: "gearshape.fill"),
        ]
    }

    private func wrap(_ vc: UIViewController, title: String, symbol: String) -> UINavigationController {
        vc.title = title
        vc.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), selectedImage: nil)
        let nav = UINavigationController(rootViewController: vc)
        nav.navigationBar.prefersLargeTitles = true
        return nav
    }

    private func tabItem(_ split: ListDetailSplitViewController, title: String, symbol: String) -> UIViewController {
        split.primaryList?.title = title
        split.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: symbol), selectedImage: nil)
        return split
    }
}

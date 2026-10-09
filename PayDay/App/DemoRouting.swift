#if DEBUG
import UIKit
import PayDayKit

/// Deterministic screen routing for App Store screenshot capture and layout
/// checks. `PAYDAY_DEMO=<screen>` picks the screen; `PAYDAY_DEMO_DOC` (a document
/// number suffix) and `PAYDAY_DEMO_CLIENT` (a name fragment) pick the record.
@MainActor
enum DemoRouting {
    static func root(for screen: String) -> UIViewController? {
        AppSettings.hasOnboarded = true
        switch screen {
        case "dashboard": return tabs(.dashboard)
        case "list", "editor", "preview", "line": return tabs(.invoices)
        case "clients", "client": return tabs(.clients)
        case "settings", "business", "paywall", "setup": return tabs(.settings)
        case "onboarding": return OnboardingViewController.makeFlow { _ in }
        default: return nil
        }
    }

    /// Opens the record or presents the sheet the screen is about, once the
    /// root is on screen and has settled into its column layout.
    static func settle(_ root: UIViewController?, screen: String) {
        guard let tabs = root as? RootViewController else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            switch screen {
            case "editor": showEditor(in: tabs)
            case "preview": showPreview(in: tabs)
            case "line": presentLine(in: tabs)
            case "client": showClient(in: tabs)
            case "business": tabs.settingsSplit.showDetail([BusinessSettingsViewController()])
            case "paywall": present(PaywallViewController(), over: tabs)
            case "setup": present(BusinessSettingsViewController(mode: .essentials), over: tabs)
            default: break
            }
        }
    }

    private static func tabs(_ tab: RootViewController.Tab) -> RootViewController {
        let tabs = RootViewController()
        tabs.selectedIndex = tab.rawValue
        return tabs
    }

    private static func document() -> Invoice? {
        DemoWorld.document(numbered: DemoWorld.launchValue("PAYDAY_DEMO_DOC"))
    }

    private static func showEditor(in tabs: RootViewController) {
        guard let invoice = document() else { return }
        let editor = InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(existing: invoice))
        tabs.invoicesSplit.showDetail([editor])
        (tabs.invoicesSplit.primaryList as? InvoiceListViewController)?.markShown(id: invoice.id)
    }

    private static func showPreview(in tabs: RootViewController) {
        guard let invoice = document() else { return }
        let editor = InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(existing: invoice))
        let preview = InvoicePreviewViewController(invoice: invoice, demoForceCompliant: true)
        tabs.invoicesSplit.showDetail([editor, preview])
        (tabs.invoicesSplit.primaryList as? InvoiceListViewController)?.markShown(id: invoice.id)
    }

    private static func presentLine(in tabs: RootViewController) {
        guard let invoice = document(), let line = invoice.lines.first else { return }
        showEditor(in: tabs)
        let editor = LineItemEditorViewController(line: line, currency: invoice.currency, onSave: { _ in }, onDelete: {})
        let nav = UINavigationController(rootViewController: editor)
        tabs.present(nav, animated: false)
    }

    private static func showClient(in tabs: RootViewController) {
        guard let client = DemoWorld.client(named: DemoWorld.launchValue("PAYDAY_DEMO_CLIENT")),
              let list = tabs.clientsSplit.primaryList as? ClientListViewController else { return }
        list.edit(client)
    }

    private static func present(_ screen: UIViewController, over tabs: UIViewController) {
        tabs.present(UINavigationController(rootViewController: screen), animated: false)
    }
}
#endif

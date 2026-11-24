#if DEBUG
import UIKit
import PayDayCore
import MidgarUI

/// Deterministic screen routing for App Store screenshot capture and layout
/// checks. `PAYDAY_DEMO=<screen>` picks the screen; `PAYDAY_DEMO_DOC` (a document
/// number suffix) and `PAYDAY_DEMO_CLIENT` (a name fragment) pick the record.
@MainActor
enum DemoRouting {
    static func root(for screen: String) -> UIViewController? {
        AppSettings.hasOnboarded = true
        switch screen {
        case "dashboard": return tabs(.dashboard)
        case "list", "editor", "preview", "reminder", "line": return tabs(.invoices)
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
            case "reminder":
                let preview = showPreview(in: tabs)
                let tone = DemoWorld.launchValue("PAYDAY_DEMO_TONE").flatMap(ReminderTone.init(rawValue:))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { preview?.startReminderForDemo(tone: tone) }
            case "line": presentLine(in: tabs)
            case "client": showClient(in: tabs)
            case "business": tabs.settingsSplit.showDetail([BusinessSettingsViewController()])
            case "paywall": present(PaywallViewController(), over: tabs)
            case "setup": present(BusinessSettingsViewController(mode: .essentials), over: tabs)
            default: break
            }
            measure(screen, in: tabs)
        }
    }

    /// Times one measured run: the launch stretch ends once the screen has
    /// settled, a list scrolls one screenful halfway through the dwell, and the
    /// stretch that ends with the dwell is named after the screen the runner
    /// screenshots next.
    private static func measure(_ screen: String, in root: UIViewController) {
        guard let dwell = DemoWorld.launchValue("PAYDAY_DEMO_DWELL").flatMap(TimeInterval.init) else { return }
        MidgarFrameWatch.shared.report("launch to \(screen)")
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell / 2) {
            scrollOnce(in: root)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dwell) {
            MidgarFrameWatch.shared.report(screen)
            MidgarFrameWatch.shared.stop()
        }
    }

    /// Scrolls the first scrollable view on screen by about a screenful, so the
    /// whole measured stretch has to lay out rows that were not on screen.
    private static func scrollOnce(in root: UIViewController) {
        guard let scroll = firstScrollable(in: root.view) else { return }
        let target = min(scroll.contentOffset.y + scroll.bounds.height * 0.9, max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom))
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: true)
    }

    private static func firstScrollable(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, view.window != nil,
           scroll.contentSize.height > scroll.bounds.height + 24 {
            return scroll
        }
        for subview in view.subviews {
            if let found = firstScrollable(in: subview) { return found }
        }
        return nil
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

    @discardableResult
    private static func showPreview(in tabs: RootViewController) -> InvoicePreviewViewController? {
        guard let invoice = document() else { return nil }
        let editor = InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(existing: invoice))
        let preview = InvoicePreviewViewController(invoice: invoice, demoForceCompliant: true)
        tabs.invoicesSplit.showDetail([editor, preview])
        (tabs.invoicesSplit.primaryList as? InvoiceListViewController)?.markShown(id: invoice.id)
        return preview
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

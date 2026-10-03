import UIKit
import PayDayKit

/// Keeps the example business off real documents: a new one started before the
/// seller is set up routes through the essentials setup first, and a document
/// still carrying the example (or no) seller can't be shared or sent.
@MainActor
enum BusinessSetupGate {
    /// Runs `proceed` at once when the business is set up; otherwise shows the
    /// essentials setup first and proceeds once it is saved or deferred.
    static func beforeNewDocument(from presenter: UIViewController, proceed: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            guard let profile = try? await BusinessRepository.shared.load(), !profile.isConfigured else { return proceed() }
            AppLogger.shared.info("new document routed to business setup", category: .ui)
            presentSetup(from: presenter) { _ in proceed() }
        }
    }

    static func presentSetup(from presenter: UIViewController, completion: @escaping @MainActor (_ saved: Bool) -> Void) {
        let setup = BusinessSettingsViewController(mode: .essentials)
        let nav = UINavigationController(rootViewController: setup)
        nav.isModalInPresentation = true
        setup.onFinish = { [weak nav] saved in
            nav?.dismiss(animated: true) { completion(saved) }
        }
        presenter.present(nav, animated: true)
    }

    /// Whether the document goes out under the user's own business.
    static func canDeliver(_ invoice: Invoice) -> Bool {
        !invoice.seller.legalName.trimmed.isEmpty && !DemoData.isSampleSeller(invoice.seller)
    }

    /// The document re-issued under `profile`'s seller and bank account. A
    /// remittance reference minted for the example business is dropped with it.
    static func reissue(_ invoice: Invoice, as profile: BusinessProfile) -> Invoice {
        var updated = invoice
        var paymentMeans = profile.paymentMeans
        paymentMeans.remittanceReference = DemoData.isSampleSeller(invoice.seller) ? "" : invoice.paymentMeans.remittanceReference
        updated.seller = profile.seller
        updated.paymentMeans = paymentMeans
        return updated
    }
}

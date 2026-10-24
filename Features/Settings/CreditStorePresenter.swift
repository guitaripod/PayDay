import AICreditsUI
import MidgarCredits
import SwiftUI
import UIKit

/// The single entry point for buying credits: presents the credit-pack store (the wallet's packs, StoreKit prices and
/// purchase) as a sheet. Never route credit top-ups to the subscription paywall. Nothing opens where the app has no
/// wallet (a test host).
@MainActor
enum CreditStorePresenter {
    static func present(from presenter: UIViewController, shortfall: Int? = nil) {
        guard let controller = makeController(shortfall: shortfall) else { return }
        presenter.present(controller, animated: true)
    }

    static func makeController(shortfall: Int? = nil) -> UIViewController? {
        guard let source = CreditsModel.shared.source else { return nil }
        let model = PayDayCreditStoreModel(
            source: source, shortfall: shortfall, restorePurchases: { try await ProAccess.shared.restoreStore() })
        let view = PayDayCreditStoreView(model: model, accountLink: AICreditsManager.accountLink)
        return UIHostingController(rootView: view)
    }
}

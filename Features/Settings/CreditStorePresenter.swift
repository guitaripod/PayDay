import AICreditsUI
import SwiftUI
import UIKit

/// The single entry point for buying credits: presents the AICredits consumable
/// credit-pack store (real StoreKit packs + purchase + restore) as a sheet.
/// Never route credit top-ups to the subscription paywall.
@MainActor
enum CreditStorePresenter {
    static func present(from presenter: UIViewController, shortfall: Int? = nil) {
        let store = AICreditsManager.store
        let view = PayDayCreditStoreView(store: store, shortfall: shortfall).environmentObject(store)
        presenter.present(UIHostingController(rootView: view), animated: true)
    }
}

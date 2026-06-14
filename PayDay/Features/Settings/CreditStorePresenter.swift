import AICreditsUI
import SwiftUI
import UIKit

/// The single entry point for buying credits: presents the AICredits consumable
/// credit-pack store (real StoreKit packs + purchase + restore) as a sheet.
/// Never route credit top-ups to the subscription paywall.
@MainActor
enum CreditStorePresenter {
    static func present(from presenter: UIViewController, shortfall: Int? = nil) {
        let view = CreditStoreView(shortfall: shortfall).environmentObject(AICreditsManager.store)
        presenter.present(UIHostingController(rootView: view), animated: true)
    }
}

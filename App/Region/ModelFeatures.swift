import Combine
import Foundation
import MidgarCore
import PayDayCore

/// The model features Pay Day offers where Midgar's servers answer for the device's country. Each screen asks this what
/// to show, and follows ``changes`` so a flip of the answer hides or shows them where the person is looking.
struct ModelFeatures: Equatable, Sendable {
    let modelsAvailable: Bool

    /// The features as the device's last answer from Midgar leaves them.
    static var current: ModelFeatures {
        ModelFeatures(modelsAvailable: MidgarModelRegion.shared.modelsAvailable)
    }

    /// Every change of the answer, delivered on the main queue with the features it leaves.
    static var changes: AnyPublisher<ModelFeatures, Never> {
        NotificationCenter.default.publisher(for: MidgarModelRegion.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .map { _ in ModelFeatures.current }
            .eraseToAnyPublisher()
    }

    /// Asks Midgar whether model features work where the device connects from. Launch and every return to the
    /// foreground call it. A test host or a demo capture reaches no Midgar service, so it asks nothing.
    static func refresh() async {
        guard PayDayMidgar.reachesMidgarServices else { return }
        let available = await MidgarModelRegion.shared.refresh(client: PayDayMidgar.shared.account)
        MidgarLog.info("model features \(available ? "available" : "unavailable") here", category: .app)
    }

    /// The Settings row that grants and withdraws AI drafting consent, which only these features use.
    var showsAIDrafting: Bool {
        modelsAvailable
    }

    /// Line items drafted from a photo or a sentence: the editor's Draft with AI row and the welcome line that promotes it.
    var showsLineItemDrafting: Bool {
        modelsAvailable
    }

    /// Whether an invoice offers a drafted payment reminder, which needs an overdue invoice and working features.
    func showsReminderDrafting(for invoice: Invoice) -> Bool {
        modelsAvailable && ReminderFlow.applies(to: invoice)
    }

    /// The credit store's line that says credits also pay for AI drafting.
    var creditsCoverAIDrafting: Bool {
        modelsAvailable
    }
}

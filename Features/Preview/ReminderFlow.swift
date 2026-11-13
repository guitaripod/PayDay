import MidgarCore
import PayDayCore
import UIKit

/// The words of a drafted payment reminder's screens.
enum ReminderCopy {
    static let title = String(localized: "Draft a Reminder", comment: "Button and sheet title: have a payment reminder email written for an overdue invoice")
    static let sends = String(
        localized: "Pay Day sends this client's name and the invoice's number, amount and due date to its AI service to write the email. It costs 1 credit.",
        comment: "Under the Draft a Reminder title, before a tone is chosen")
    static let failedTitle = String(localized: "Couldn't draft the reminder", comment: "Alert title")
    static let unusable = String(
        localized: "The draft didn't state this invoice correctly, so it was thrown away. Try again.",
        comment: "Alert message when a drafted reminder failed its checks")
    static let offline = String(localized: "The AI request failed — check your connection and try again.")

    static func name(of tone: ReminderTone) -> String {
        switch tone {
        case .friendly: return String(localized: "Friendly", comment: "Tone of a payment reminder")
        case .firm: return String(localized: "Firm", comment: "Tone of a payment reminder")
        case .final: return String(localized: "Final Reminder", comment: "Tone of a payment reminder: the last one")
        }
    }
}

/// Drafting a payment reminder for an overdue invoice: consent to AI drafting the first time, then the tone under a
/// line saying what is sent and what it costs, the draft, and the share sheet with the email and the invoice's PDF.
@MainActor
final class ReminderFlow {
    nonisolated static let cost = 1

    private let invoice: Invoice
    private weak var host: UIViewController?
    private let anchor: UIBarButtonItem
    private let attachment: () -> URL?
    private var work: Task<Void, Never>?

    /// - Parameter attachment: writes the invoice's PDF for sharing and returns where, or nil when there is none yet.
    init(invoice: Invoice, host: UIViewController, anchor: UIBarButtonItem, attachment: @escaping () -> URL?) {
        self.invoice = invoice
        self.host = host
        self.anchor = anchor
        self.attachment = attachment
    }

    /// Whether a reminder makes sense: an invoice that is past its due date and not paid.
    nonisolated static func applies(to invoice: Invoice) -> Bool {
        invoice.type == .invoice && invoice.status == .overdue
    }

    func start() {
        guard work == nil, let host else { return }
        guard AppSettings.aiConsentGranted else {
            let consent = AIConsentViewController { [weak self, weak host] granted in
                AppSettings.aiConsentGranted = granted
                guard granted else { return }
                host?.dismiss(animated: true) { self?.chooseTone() }
            }
            host.present(UINavigationController(rootViewController: consent), animated: true)
            return
        }
        chooseTone()
    }

    private func chooseTone() {
        let sheet = UIAlertController(title: ReminderCopy.title, message: ReminderCopy.sends, preferredStyle: .actionSheet)
        for tone in ReminderTone.allCases {
            let action = UIAlertAction(title: ReminderCopy.name(of: tone), style: .default) { [weak self] _ in self?.draft(tone) }
            action.accessibilityIdentifier = "reminder.tone.\(tone.rawValue)"
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        sheet.popoverPresentationController?.barButtonItem = anchor
        host?.present(sheet, animated: true)
    }

    private func draft(_ tone: ReminderTone) {
        anchor.isEnabled = false
        work = Task { [weak self, invoice] in
            let balance = await CreditsModel.shared.refresh() ?? CreditsModel.shared.balance
            if let shortfall = CreditsModel.shortfall(cost: Self.cost, balance: balance) {
                self?.finish { host in CreditStorePresenter.present(from: host, shortfall: shortfall) }
                return
            }
            do {
                let draft = try await InvoiceAIService().reminder(for: invoice, tone: tone)
                MidgarLog.info("reminder drafted for \(invoice.id), tone \(tone.rawValue)", category: .invoice)
                self?.finish { [weak self] host in self?.share(draft, from: host) }
            } catch {
                MidgarLog.error("reminder draft failed for \(invoice.id): \(error)", category: .invoice)
                await CreditsModel.shared.refresh()
                self?.finish { host in
                    if CreditsModel.shared.isEmpty {
                        CreditStorePresenter.present(from: host)
                    } else {
                        let message = error is InvoiceAIService.ReminderFailure ? ReminderCopy.unusable : ReminderCopy.offline
                        let alert = UIAlertController(title: ReminderCopy.failedTitle, message: message, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                        host.present(alert, animated: true)
                    }
                }
            }
        }
    }

    /// Ends the request and shows its outcome, when the screen is still there.
    private func finish(_ outcome: (UIViewController) -> Void) {
        work = nil
        anchor.isEnabled = true
        guard let host, host.view.window != nil, host.presentedViewController == nil else { return }
        outcome(host)
    }

    private func share(_ draft: ReminderDraft, from host: UIViewController) {
        #if DEBUG
        Self.keepForDemo(draft)
        #endif
        var items: [Any] = [ReminderMessage(draft)]
        if let pdf = attachment() { items.append(pdf) }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.barButtonItem = anchor
        host.present(sheet, animated: true)
        Task { await CreditsModel.shared.refresh() }
    }
}

#if DEBUG
extension ReminderFlow {
    /// The file a demo run leaves its draft in, so a capture script can read what was drafted.
    static let demoDraftURL = FileManager.default.temporaryDirectory.appendingPathComponent("reminder-draft.txt")

    /// Starts the flow for a demo capture: with a tone, drafts at once as if it had been chosen.
    func startForDemo(tone: ReminderTone?) {
        guard let tone else { return start() }
        try? FileManager.default.removeItem(at: Self.demoDraftURL)
        draft(tone)
    }

    fileprivate static func keepForDemo(_ draft: ReminderDraft) {
        guard DemoWorld.isActive else { return }
        try? Data("\(draft.subject)\n\n\(draft.body)\n".utf8).write(to: demoDraftURL)
    }
}
#endif

/// A drafted reminder as the share sheet takes it: the body as text, and its subject where the target has one.
final class ReminderMessage: NSObject, UIActivityItemSource {
    private let draft: ReminderDraft

    init(_ draft: ReminderDraft) {
        self.draft = draft
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        draft.body
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        draft.body
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        draft.subject
    }
}

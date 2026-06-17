import Combine
import Foundation
import PayDayKit

/// Owns the in-progress document. Every mutation republishes the whole invoice
/// and its freshly-computed totals, so the view stays a pure function of state.
@MainActor
final class InvoiceEditorViewModel {
    let invoicePublisher = PassthroughSubject<Invoice, Never>()
    let totalsPublisher = PassthroughSubject<ComputedTotals, Never>()
    let validationPublisher = PassthroughSubject<[ValidationIssue], Never>()
    let savedPublisher = PassthroughSubject<Invoice, Never>()

    private(set) var invoice: Invoice
    let isNew: Bool
    private var numberReserved = false
    /// The sequence number peeked on open. A `setNumber` that still equals this
    /// is not a manual edit, so first save still reserves (advancing the counter
    /// to the same value); only a genuinely different number is treated as manual.
    private var peekedNumber = ""
    /// Set once the user edits the number to something other than the peek, so the
    /// auto-reserve on first save never overwrites a custom number.
    private var numberIsManual = false

    private let invoices: InvoiceRepository
    private let clients: ClientRepository
    private let business: BusinessRepository

    init(
        kind: DocumentType = .invoice,
        existing: Invoice? = nil,
        invoices: InvoiceRepository = .shared,
        clients: ClientRepository = .shared,
        business: BusinessRepository = .shared
    ) {
        self.invoices = invoices
        self.clients = clients
        self.business = business
        if let existing {
            self.invoice = existing
            self.isNew = false
        } else {
            let today = Format.today()
            self.invoice = Invoice(
                id: UUID().uuidString,
                type: kind,
                number: "",
                issueDate: today,
                dueDate: today.adding(days: AppSettings.defaultPaymentTermDays),
                currency: Currency(AppSettings.defaultCurrencyCode),
                seller: Party(id: "business", legalName: ""),
                buyer: Party(id: "", legalName: ""))
            self.isNew = true
        }
    }

    func start() {
        Task {
            if isNew {
                let profile = try? await business.load()
                if let profile {
                    invoice.seller = profile.seller
                    invoice.currency = profile.currency
                    invoice.paymentMeans = profile.paymentMeans
                    invoice.paymentTerms = profile.defaultPaymentTerms
                }
                // Peek (do NOT advance) on open — the number is only reserved on
                // the first save, so abandoned drafts don't burn invoice numbers.
                let seq = (try? await business.sequence(for: invoice.type))
                    ?? NumberSequence(type: invoice.type, template: NumberSequence.defaultTemplate(for: invoice.type))
                invoice.number = seq.peek(on: invoice.issueDate)
                peekedNumber = invoice.number
            }
            publish()
        }
    }

    private func publish() {
        invoicePublisher.send(invoice)
        totalsPublisher.send(invoice.totals())
        validationPublisher.send(invoice.type.isEInvoiceable ? InvoiceValidator.validate(invoice) : [])
    }

    func setBuyer(_ party: Party) { invoice.buyer = party; publish() }
    func setNumber(_ value: String) {
        invoice.number = value
        numberIsManual = value.trimmed != peekedNumber
        publish()
    }
    func setIssueDate(_ date: CalendarDate) {
        invoice.issueDate = date
        invoice.dueDate = date.adding(days: AppSettings.defaultPaymentTermDays)
        publish()
    }
    func setDueDate(_ date: CalendarDate) { invoice.dueDate = date; publish() }
    func setNote(_ value: String) { invoice.note = value; publish() }
    func setPaymentTerms(_ value: String) { invoice.paymentTerms = value; publish() }

    func upsert(_ line: LineItem) {
        if let index = invoice.lines.firstIndex(where: { $0.id == line.id }) {
            invoice.lines[index] = line
        } else {
            invoice.lines.append(line)
        }
        publish()
    }

    func removeLine(id: String) {
        invoice.lines.removeAll { $0.id == id }
        publish()
    }

    func removeLine(at index: Int) {
        guard invoice.lines.indices.contains(index) else { return }
        invoice.lines.remove(at: index)
        publish()
    }

    func duplicateLine(id: String) {
        guard let index = invoice.lines.firstIndex(where: { $0.id == id }) else { return }
        var copy = invoice.lines[index]
        copy.id = UUID().uuidString
        invoice.lines.insert(copy, at: index + 1)
        publish()
    }

    /// Reorder a line (drag-to-reorder in the editor). Fires the full publish so
    /// the VC's `invoice` mirror resyncs; the table has already committed the move
    /// animation by the time the reload runs, so there is no animation fight.
    func moveLine(from: Int, to: Int) {
        guard invoice.lines.indices.contains(from), to >= 0, to <= invoice.lines.count else { return }
        let line = invoice.lines.remove(at: from)
        invoice.lines.insert(line, at: min(to, invoice.lines.count))
        publish()
    }

    func appendDraftedLines(_ drafts: [InvoiceAIService.DraftedLine]) {
        let rate = Decimal(AppSettings.defaultVATRatePercent)
        for draft in drafts {
            invoice.lines.append(LineItem(
                id: UUID().uuidString, name: draft.name, details: draft.details,
                quantity: draft.quantity, unitPrice: draft.unitPrice,
                vatCategory: .standard, vatRatePercent: rate))
        }
        publish()
    }

    func newLineTemplate() -> LineItem {
        LineItem(id: UUID().uuidString, name: "", quantity: 1, unit: .hour, unitPrice: 0,
                 vatCategory: .standard, vatRatePercent: Decimal(AppSettings.defaultVATRatePercent))
    }

    func save(completion: ((Invoice?) -> Void)? = nil) {
        Task {
            do {
                if isNew && !numberReserved && !numberIsManual {
                    if let reserved = try? await business.nextNumber(for: invoice.type, on: invoice.issueDate) {
                        invoice.number = reserved
                    }
                    numberReserved = true
                }
                if !invoice.buyer.id.isEmpty { try await clients.save(invoice.buyer) }
                try await invoices.save(invoice)
                publish()
                savedPublisher.send(invoice)
                completion?(invoice)
            } catch {
                AppLogger.shared.error("save failed: \(error)", category: .db)
                completion?(nil)
            }
        }
    }
}

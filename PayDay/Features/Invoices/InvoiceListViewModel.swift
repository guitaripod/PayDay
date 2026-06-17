import Combine
import Foundation
import PayDayKit

@MainActor
final class InvoiceListViewModel {
    let documentsPublisher = PassthroughSubject<[Invoice], Never>()
    let errorPublisher = PassthroughSubject<String, Never>()

    private static let numberAllocationFailure = "Couldn't allocate a number — try again"

    var kind: DocumentType
    private let invoices: InvoiceRepository

    init(kind: DocumentType, invoices: InvoiceRepository = .shared) {
        self.kind = kind
        self.invoices = invoices
    }

    func load() {
        Task {
            do {
                if kind == .invoice { try? await invoices.refreshOverdue(today: Format.today()) }
                documentsPublisher.send(try await invoices.documents(ofType: kind))
            } catch {
                AppLogger.shared.error("list load failed: \(error)", category: .db)
                documentsPublisher.send([])
            }
        }
    }

    func convertToInvoice(_ estimate: Invoice) {
        Task {
            guard let number = try? await BusinessRepository.shared.nextNumber(for: .invoice, on: Format.today()) else {
                errorPublisher.send(Self.numberAllocationFailure)
                return
            }
            _ = try? await invoices.makeInvoice(fromEstimate: estimate, number: number, today: Format.today())
            load()
        }
    }

    func delete(_ invoice: Invoice) {
        Task {
            try? await invoices.delete(id: invoice.id)
            load()
        }
    }

    func duplicate(_ invoice: Invoice) {
        Task {
            var copy = invoice
            copy.id = UUID().uuidString
            copy.status = .draft
            guard let number = try? await BusinessRepository.shared.nextNumber(for: copy.type, on: Format.today()) else {
                errorPublisher.send(Self.numberAllocationFailure)
                return
            }
            copy.number = number
            try? await invoices.save(copy)
            load()
        }
    }

    func markPaid(_ invoice: Invoice) {
        Task {
            var updated = invoice
            updated.status = .paid
            try? await invoices.save(updated)
            load()
        }
    }
}

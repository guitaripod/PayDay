import Combine
import Foundation
import PayDayKit

@MainActor
final class DashboardViewModel {
    struct Snapshot {
        let outstanding: Money
        let invoiceCount: Int
        let estimateCount: Int
        let overdueCount: Int
        let recent: [Invoice]
    }

    let snapshotPublisher = PassthroughSubject<Snapshot, Never>()
    let isProPublisher = PassthroughSubject<Bool, Never>()

    private let invoices: InvoiceRepository
    private let currencyCode: String

    init(invoices: InvoiceRepository = .shared, currencyCode: String = AppSettings.defaultCurrencyCode) {
        self.invoices = invoices
        self.currencyCode = currencyCode
    }

    func load() {
        Task {
            do {
                try? await invoices.refreshOverdue(today: Format.today())
                let all = try await invoices.all()
                let currency = Currency(currencyCode)
                let outstanding = Money(minorUnits: try await invoices.outstandingMinorUnits(), currency: currency)
                let snapshot = Snapshot(
                    outstanding: outstanding,
                    invoiceCount: all.filter { $0.type == .invoice }.count,
                    estimateCount: all.filter { $0.type == .estimate }.count,
                    overdueCount: all.filter { $0.status == .overdue }.count,
                    recent: Array(all.prefix(5)))
                snapshotPublisher.send(snapshot)
            } catch {
                AppLogger.shared.error("dashboard load failed: \(error)", category: .db)
            }
        }
        Task { isProPublisher.send(await AICreditsManager.store.client.isPremium()) }
    }
}

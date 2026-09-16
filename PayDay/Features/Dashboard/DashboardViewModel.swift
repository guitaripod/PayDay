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
        let sellerConfigured: Bool
        let sellerCountryCode: String
        let sellerPeppolConfigured: Bool
    }

    let snapshotPublisher = PassthroughSubject<Snapshot, Never>()

    private let invoices: InvoiceRepository
    private let business: BusinessRepository
    private let currencyCode: String

    init(invoices: InvoiceRepository = .shared,
         business: BusinessRepository = .shared,
         currencyCode: String = AppSettings.defaultCurrencyCode) {
        self.invoices = invoices
        self.business = business
        self.currencyCode = currencyCode
    }

    func load() {
        Task {
            do {
                try? await invoices.refreshOverdue(today: Format.today())
                let all = try await invoices.all()
                let currency = Currency(currencyCode)
                let outstanding = Money(minorUnits: try await invoices.outstandingMinorUnits(currencyCode: currencyCode), currency: currency)
                let profile = try? await business.load()
                let sellerConfigured = profile?.isConfigured ?? true
                let snapshot = Snapshot(
                    outstanding: outstanding,
                    invoiceCount: all.filter { $0.type == .invoice }.count,
                    estimateCount: all.filter { $0.type == .estimate }.count,
                    overdueCount: all.filter { $0.status == .overdue }.count,
                    recent: Array(all.prefix(5)),
                    sellerConfigured: sellerConfigured,
                    sellerCountryCode: Self.countryCode(for: profile?.seller),
                    sellerPeppolConfigured: !(profile?.seller.peppolParticipant.isEmpty ?? true))
                snapshotPublisher.send(snapshot)
            } catch {
                AppLogger.shared.error("dashboard load failed: \(error)", category: .db)
            }
        }
    }

    /// The country whose e-invoicing rules apply to the seller: the business
    /// address first, then the VAT prefix, then the device region.
    static func countryCode(for seller: Party?) -> String {
        #if DEBUG
        if let forced = ProcessInfo.processInfo.environment["PAYDAY_DEMO_COUNTRY"], !forced.isEmpty { return forced }
        #endif
        if let code = seller?.address.countryCode, !code.isEmpty { return code }
        if let seller, seller.hasVATID { return seller.vatCountryPrefix }
        return Locale.current.region?.identifier ?? ""
    }
}

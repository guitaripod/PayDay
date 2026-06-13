import Foundation
import GRDB
import PayDayKit

/// Seeds a configured business, two clients, and two worked-example documents on
/// first launch — so a new user (and App Review) immediately sees real output.
///
/// Runs **synchronously in a single transaction before any UI is built**: the
/// dashboard/list load on `viewDidLoad`/`viewWillAppear`, so an async seed would
/// race them and the screen would show empty until the next reload.
enum DemoSeeder {
    static func seedIfNeeded(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        guard !AppSettings.didSeedDemo else { return }
        do {
            try dbQueue.write { db in
                let business = BusinessProfile(
                    seller: DemoData.sampleSeller(),
                    defaultCurrencyCode: "EUR",
                    defaultVATRatePercent: 25.5,
                    defaultPaymentTermDays: 14,
                    defaultEInvoiceProfile: .en16931,
                    paymentMeans: PaymentMeans(
                        method: .creditTransfer, iban: "FI21 1234 5600 0007 85", bic: "OKOYFIHH",
                        accountName: "Aurora Studio Oy"),
                    defaultPaymentTerms: "Net 14 days.")
                try BusinessRecord(business).insert(db)

                let invoice = DemoData.sampleInvoice()
                let intra = DemoData.sampleIntraCommunityInvoice()
                try ClientRecord(invoice.buyer).insert(db)
                try ClientRecord(intra.buyer).insert(db)
                try DocumentRecord(invoice).insert(db)
                try DocumentRecord(intra).insert(db)
                try SequenceRecord(NumberSequence(
                    type: .invoice, template: NumberSequence.defaultTemplate(for: .invoice), nextValue: 9)).insert(db)
            }
            AppSettings.didSeedDemo = true
            AppLogger.shared.info("seeded demo data", category: .db)
        } catch {
            AppLogger.shared.error("demo seed failed: \(error)", category: .db)
        }
    }
}

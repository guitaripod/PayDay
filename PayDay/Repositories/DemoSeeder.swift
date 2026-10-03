import Foundation
import GRDB
import PayDayKit

/// Seeds an example business, two clients, and two worked-example documents on
/// first launch — so a new user (and App Review) immediately sees real output.
/// The example business stays recognisable (`BusinessProfile.isDemo`), so it
/// never pre-fills a real invoice and is replaced by the user's own on setup.
///
/// Runs **synchronously in a single transaction before any UI is built**: the
/// dashboard/list load on `viewDidLoad`/`viewWillAppear`, so an async seed would
/// race them and the screen would show empty until the next reload.
enum DemoSeeder {
    static func seedIfNeeded(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        guard !AppSettings.didSeedDemo else { return }
        do {
            try dbQueue.write { db in
                let business = BusinessProfile.demo()
                try BusinessRecord(business).insert(db)

                let invoice = DemoData.sampleInvoice()
                let intra = DemoData.sampleIntraCommunityInvoice()
                let estimate = DemoData.sampleEstimate()
                try ClientRecord(invoice.buyer).insert(db)
                try ClientRecord(intra.buyer).insert(db)
                try ClientRecord(estimate.buyer).insert(db)
                try DocumentRecord(invoice).insert(db)
                try DocumentRecord(intra).insert(db)
                try DocumentRecord(estimate).insert(db)
                try SequenceRecord(NumberSequence(
                    type: .invoice, template: NumberSequence.defaultTemplate(for: .invoice), nextValue: 9)).insert(db)
                try SequenceRecord(NumberSequence(
                    type: .estimate, template: NumberSequence.defaultTemplate(for: .estimate), nextValue: 4)).insert(db)
            }
            AppSettings.didSeedDemo = true
            AppLogger.shared.info("seeded demo data", category: .db)
        } catch {
            AppLogger.shared.error("demo seed failed: \(error)", category: .db)
        }
    }
}

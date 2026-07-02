import Foundation
import GRDB
import PayDayKit

/// Async access to stored documents. An actor so concurrent screens (dashboard,
/// list, editor) never race on the database queue.
actor InvoiceRepository {
    static let shared = InvoiceRepository()

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func all() throws -> [Invoice] {
        try dbQueue.read { db in
            try DocumentRecord
                .order(Column("issueDate").desc, Column("updatedAt").desc)
                .fetchAll(db)
                .compactMap(\.invoice)
        }
    }

    func documents(ofType type: DocumentType) throws -> [Invoice] {
        try dbQueue.read { db in
            try DocumentRecord
                .filter(Column("type") == type.rawValue)
                .order(Column("issueDate").desc, Column("updatedAt").desc)
                .fetchAll(db)
                .compactMap(\.invoice)
        }
    }

    func fetch(id: String) throws -> Invoice? {
        try dbQueue.read { db in
            try DocumentRecord.fetchOne(db, key: id)?.invoice
        }
    }

    @discardableResult
    func save(_ invoice: Invoice) throws -> Invoice {
        try dbQueue.write { db in
            try DocumentRecord(invoice).save(db)
        }
        return invoice
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in
            try DocumentRecord.deleteOne(db, key: id)
        }
    }

    /// Outstanding receivables: sum of payable amounts on issued, unpaid invoices
    /// in a single currency (summing mixed currencies would be meaningless).
    func outstandingMinorUnits(currencyCode: String) throws -> Int {
        let unpaid: Set<String> = ["sent", "viewed", "partiallyPaid", "overdue"]
        return try dbQueue.read { db in
            try Int.fetchOne(
                db,
                DocumentRecord
                    .filter(Column("type") == DocumentType.invoice.rawValue)
                    .filter(Column("currency") == currencyCode)
                    .filter(unpaid.contains(Column("status")))
                    .select(sum(Column("payableMinor")))) ?? 0
        }
    }

    func count(ofType type: DocumentType) throws -> Int {
        try dbQueue.read { db in
            try DocumentRecord.filter(Column("type") == type.rawValue).fetchCount(db)
        }
    }

    /// Mark a draft document as sent. A no-op for any other status so a share or
    /// transmission can never regress a paid/overdue invoice back to `sent`.
    @discardableResult
    func markSent(id: String) throws -> Invoice? {
        try dbQueue.write { db in
            guard var invoice = try DocumentRecord.fetchOne(db, key: id)?.invoice,
                  invoice.status == .draft else { return nil }
            invoice.status = .sent
            try DocumentRecord(invoice).update(db)
            return invoice
        }
    }

    /// Flip issued-but-unpaid invoices whose due date has passed to `overdue`.
    /// Idempotent; safe to call on every foreground.
    @discardableResult
    func refreshOverdue(today: CalendarDate) throws -> Int {
        try dbQueue.write { db in
            let candidates = try DocumentRecord
                .filter(Column("type") == DocumentType.invoice.rawValue)
                .filter([DocumentStatus.sent.rawValue, DocumentStatus.viewed.rawValue, DocumentStatus.partiallyPaid.rawValue].contains(Column("status")))
                .filter(Column("dueDate") < today.iso8601)
                .fetchAll(db)
            var changed = 0
            for record in candidates {
                guard var invoice = record.invoice else { continue }
                invoice.status = .overdue
                try DocumentRecord(invoice).update(db)
                changed += 1
            }
            return changed
        }
    }

    /// Create a draft invoice from an estimate, carrying over parties and lines.
    func makeInvoice(fromEstimate estimate: Invoice, number: String, today: CalendarDate) throws -> Invoice {
        var invoice = estimate
        invoice.id = UUID().uuidString
        invoice.type = .invoice
        invoice.status = .draft
        invoice.number = number
        invoice.issueDate = today
        invoice.dueDate = today.adding(days: 14)
        try save(invoice)
        return invoice
    }
}

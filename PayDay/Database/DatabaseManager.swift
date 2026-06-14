import Foundation
import GRDB

final class DatabaseManager: @unchecked Sendable {
    static let shared = DatabaseManager()

    let dbQueue: DatabaseQueue

    private init() {
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = support.appendingPathComponent("payday", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let path = dir.appendingPathComponent("payday.sqlite").path
            let queue = try DatabaseQueue(path: path)
            try Self.runMigrations(queue)
            dbQueue = queue
            AppLogger.shared.info("database opened at \(path)", category: .db)
        } catch {
            // Don't crash-loop on a corrupt store / failed migration / sandbox
            // issue — degrade to an in-memory database so the app still launches.
            // Logged at .error; an in-memory DatabaseQueue cannot fail to open.
            AppLogger.shared.error("database open failed, falling back to in-memory: \(error)", category: .db)
            // swiftlint:disable:next force_try
            let queue = try! DatabaseQueue()
            try? Self.runMigrations(queue)
            dbQueue = queue
        }
    }

    init(inMemoryName: String) throws {
        dbQueue = try DatabaseQueue(named: inMemoryName)
        try Self.runMigrations(dbQueue)
    }

    /// Wipe all on-device business data — used by account deletion. The schema
    /// (tables + migrations) is kept; only rows are removed.
    func eraseAllData() throws {
        try dbQueue.write { db in
            for table in ["documents", "clients", "business", "sequences"] {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }

    private static func runMigrations(_ db: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "documents") { t in
                t.primaryKey("id", .text)
                t.column("type", .text).notNull()
                t.column("status", .text).notNull().indexed()
                t.column("number", .text).notNull()
                t.column("clientId", .text).notNull()
                t.column("clientName", .text).notNull()
                t.column("issueDate", .text).notNull()
                t.column("dueDate", .text).notNull()
                t.column("currency", .text).notNull()
                t.column("payableMinor", .integer).notNull().defaults(to: 0)
                t.column("updatedAt", .datetime).notNull()
                t.column("payload", .blob).notNull()
            }
            try db.create(table: "clients") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().indexed()
                t.column("countryCode", .text).notNull()
                t.column("vatID", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("payload", .blob).notNull()
            }
            try db.create(table: "business") { t in
                t.primaryKey("id", .integer)
                t.column("payload", .blob).notNull()
            }
            try db.create(table: "sequences") { t in
                t.primaryKey("type", .text)
                t.column("template", .text).notNull()
                t.column("nextValue", .integer).notNull().defaults(to: 1)
            }
        }
        try migrator.migrate(db)
    }
}

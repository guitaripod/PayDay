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
            dbQueue = try DatabaseQueue(path: path)
            try Self.runMigrations(dbQueue)
            AppLogger.shared.info("database opened at \(path)", category: .db)
        } catch {
            fatalError("Database init failed: \(error)")
        }
    }

    init(inMemoryName: String) throws {
        dbQueue = try DatabaseQueue(named: inMemoryName)
        try Self.runMigrations(dbQueue)
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

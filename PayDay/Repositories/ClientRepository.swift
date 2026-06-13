import Foundation
import GRDB
import PayDayKit

actor ClientRepository {
    static let shared = ClientRepository()

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func all() throws -> [Party] {
        try dbQueue.read { db in
            try ClientRecord.order(Column("name")).fetchAll(db).compactMap(\.party)
        }
    }

    func fetch(id: String) throws -> Party? {
        try dbQueue.read { db in
            try ClientRecord.fetchOne(db, key: id)?.party
        }
    }

    @discardableResult
    func save(_ party: Party) throws -> Party {
        try dbQueue.write { db in
            try ClientRecord(party).save(db)
        }
        return party
    }

    func delete(id: String) throws {
        _ = try dbQueue.write { db in
            try ClientRecord.deleteOne(db, key: id)
        }
    }

    func count() throws -> Int {
        try dbQueue.read { db in try ClientRecord.fetchCount(db) }
    }
}

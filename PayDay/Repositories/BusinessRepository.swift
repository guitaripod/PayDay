import Foundation
import GRDB
import PayDayKit

actor BusinessRepository {
    static let shared = BusinessRepository()

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) {
        self.dbQueue = dbQueue
    }

    func load() throws -> BusinessProfile {
        try dbQueue.read { db in
            try BusinessRecord.fetchOne(db, key: 1)?.profile
        } ?? BusinessProfile()
    }

    func save(_ profile: BusinessProfile) throws {
        try dbQueue.write { db in
            try BusinessRecord(profile).save(db)
        }
    }

    // MARK: Number sequences

    func sequence(for type: DocumentType) throws -> NumberSequence {
        try dbQueue.read { db in
            try SequenceRecord.fetchOne(db, key: type.rawValue)?.sequence
        } ?? NumberSequence(type: type, template: NumberSequence.defaultTemplate(for: type))
    }

    /// Reserve and return the next number for a type, advancing the stored
    /// counter atomically so two invoices can never share a number.
    func nextNumber(for type: DocumentType, on date: CalendarDate) throws -> String {
        try dbQueue.write { db in
            var seq = try SequenceRecord.fetchOne(db, key: type.rawValue)?.sequence
                ?? NumberSequence(type: type, template: NumberSequence.defaultTemplate(for: type))
            let rendered = seq.advance(on: date)
            try SequenceRecord(seq).save(db)
            return rendered
        }
    }

    func saveSequence(_ sequence: NumberSequence) throws {
        try dbQueue.write { db in
            try SequenceRecord(sequence).save(db)
        }
    }
}

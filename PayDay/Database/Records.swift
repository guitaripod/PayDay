import Foundation
import GRDB
import PayDayKit

/// Persistence wraps the Kit value types as JSON payloads with a few indexed,
/// queryable columns for listing and sorting. The Kit `Invoice` / `Party` stay
/// the single source of truth; we never shred them into a sprawling schema.

private let jsonEncoder = JSONEncoder()
private let jsonDecoder = JSONDecoder()

struct DocumentRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: String
    var type: String
    var status: String
    var number: String
    var clientId: String
    var clientName: String
    var issueDate: String
    var dueDate: String
    var currency: String
    var payableMinor: Int
    var updatedAt: Date
    var payload: Data

    static let databaseTableName = "documents"

    init(_ invoice: Invoice, updatedAt: Date = Date()) {
        self.id = invoice.id
        self.type = invoice.type.rawValue
        self.status = invoice.status.rawValue
        self.number = invoice.number
        self.clientId = invoice.buyer.id
        self.clientName = invoice.buyer.displayName
        self.issueDate = invoice.issueDate.iso8601
        self.dueDate = invoice.dueDate.iso8601
        self.currency = invoice.currency.code
        self.payableMinor = invoice.totals().summary.payableAmount.minorUnits
        self.updatedAt = updatedAt
        self.payload = (try? jsonEncoder.encode(invoice)) ?? Data()
    }

    var invoice: Invoice? {
        do {
            return try jsonDecoder.decode(Invoice.self, from: payload)
        } catch {
            AppLogger.shared.error("document \(id) failed to decode: \(error)", category: .db)
            return nil
        }
    }
}

struct ClientRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: String
    var name: String
    var countryCode: String
    var vatID: String
    var updatedAt: Date
    var payload: Data

    static let databaseTableName = "clients"

    init(_ party: Party, updatedAt: Date = Date()) {
        self.id = party.id
        self.name = party.displayName
        self.countryCode = party.address.countryCode
        self.vatID = party.vatID
        self.updatedAt = updatedAt
        self.payload = (try? jsonEncoder.encode(party)) ?? Data()
    }

    var party: Party? {
        try? jsonDecoder.decode(Party.self, from: payload)
    }
}

struct BusinessRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64
    var payload: Data

    static let databaseTableName = "business"

    init(_ profile: BusinessProfile) {
        self.id = 1
        self.payload = (try? jsonEncoder.encode(profile)) ?? Data()
    }

    var profile: BusinessProfile? {
        try? jsonDecoder.decode(BusinessProfile.self, from: payload)
    }
}

struct SequenceRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    var type: String
    var template: String
    var nextValue: Int

    static let databaseTableName = "sequences"

    init(_ sequence: NumberSequence) {
        self.type = sequence.type.rawValue
        self.template = sequence.template
        self.nextValue = sequence.nextValue
    }

    var sequence: NumberSequence? {
        guard let type = DocumentType(rawValue: type) else { return nil }
        return NumberSequence(type: type, template: template, nextValue: nextValue)
    }
}

#if DEBUG
import Foundation
import GRDB
import PayDayKit

/// An offline, deterministic freelancer business for App Store captures and
/// layout checks: a fictional seller in the device's market, a dozen clients
/// across the EU, and invoices in every status, with amounts in the device
/// locale's currency. Switched on by `PAYDAY_DEMO`; wiped and reseeded in one
/// transaction on every launch, so relaunching can never crash or accumulate.
enum DemoWorld {
    static var isActive: Bool { launchValue("PAYDAY_DEMO") != nil }

    static func launchValue(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key].flatMap { $0.isEmpty ? nil : $0 }
    }

    static func reseed(dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue, today: CalendarDate = Format.today()) {
        let world = World(today: today, locale: .current)
        do {
            try dbQueue.write { db in
                for table in ["documents", "clients", "business", "sequences"] {
                    try db.execute(sql: "DELETE FROM \(table)")
                }
                try BusinessRecord(world.profile).insert(db)
                for (index, client) in world.clients.enumerated() {
                    try ClientRecord(client, updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))).insert(db)
                }
                for (index, document) in world.documents.enumerated() {
                    try DocumentRecord(document, updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))).insert(db)
                }
                try SequenceRecord(NumberSequence(
                    type: .invoice, template: NumberSequence.defaultTemplate(for: .invoice), nextValue: world.nextInvoiceNumber)).insert(db)
                try SequenceRecord(NumberSequence(
                    type: .estimate, template: NumberSequence.defaultTemplate(for: .estimate), nextValue: world.nextEstimateNumber)).insert(db)
            }
            AppSettings.didSeedDemo = true
            AppSettings.defaultCurrencyCode = world.currency.code
            AppSettings.defaultVATRatePercent = world.profile.defaultVATRatePercent
            AppLogger.shared.info("seeded demo world", category: .db)
        } catch {
            AppLogger.shared.error("demo world seed failed: \(error)", category: .db)
        }
    }

    /// The seeded document whose number ends in `suffix`, or the first one.
    static func document(numbered suffix: String?, dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) -> Invoice? {
        let all = (try? dbQueue.read { db in
            try DocumentRecord.order(Column("issueDate").desc, Column("updatedAt").desc).fetchAll(db).compactMap(\.invoice)
        }) ?? []
        guard let suffix else { return all.first { $0.type == .invoice } }
        return all.first { $0.number.hasSuffix(suffix) }
    }

    /// The seeded client whose name contains `fragment`, or the first one.
    static func client(named fragment: String?, dbQueue: DatabaseQueue = DatabaseManager.shared.dbQueue) -> Party? {
        let all = (try? dbQueue.read { db in
            try ClientRecord.order(Column("name")).fetchAll(db).compactMap(\.party)
        }) ?? []
        guard let fragment else { return all.first }
        return all.first { $0.displayName.localizedCaseInsensitiveContains(fragment) }
    }
}

private struct World {
    let today: CalendarDate
    let currency: Currency
    let market: Market
    let seller: Party
    let profile: BusinessProfile
    let clients: [Party]
    let documents: [Invoice]
    let nextInvoiceNumber: Int
    let nextEstimateNumber: Int

    init(today: CalendarDate, locale: Locale) {
        self.today = today
        let currency = Currency(locale.currency?.identifier ?? "EUR")
        let market = Market.forRegion(locale.region?.identifier)
        let seller = market.seller()
        let clients = ClientBook.all()
        let pricing = Pricing(currency: currency)
        let drafter = Drafter(today: today, seller: seller, market: market, currency: currency, pricing: pricing)
        self.currency = currency
        self.market = market
        self.seller = seller
        self.clients = clients
        self.documents = drafter.documents(clients: clients)
        self.nextInvoiceNumber = Drafter.firstInvoiceNumber + drafter.invoiceCount
        self.nextEstimateNumber = Drafter.firstEstimateNumber + drafter.estimateCount
        self.profile = BusinessProfile(
            seller: seller,
            defaultCurrencyCode: currency.code,
            defaultVATRatePercent: NSDecimalNumber(decimal: market.vatRate).doubleValue,
            defaultPaymentTermDays: 14,
            defaultEInvoiceProfile: .en16931,
            paymentMeans: market.paymentMeans(),
            defaultPaymentTerms: "Net 14 days.")
    }
}

private struct Pricing {
    let currency: Currency

    /// A EUR-scale list price expressed in the device currency, rounded to the
    /// step a person would actually quote.
    func price(_ euros: Decimal) -> Decimal {
        let scaled = NSDecimalNumber(decimal: euros * rate).doubleValue
        let step: Double
        switch scaled {
        case ..<1_000: step = 5
        case ..<10_000: step = 50
        case ..<100_000: step = 500
        default: step = 5_000
        }
        return Decimal((scaled / step).rounded() * step)
    }

    private var rate: Decimal {
        switch currency.code {
        case "USD": return 1.1
        case "GBP": return 0.85
        case "JPY": return 160
        case "KRW": return 1_450
        case "CNY": return 7.8
        case "TWD": return 35
        case "BRL": return 6
        case "PLN": return 4.3
        default: return 1
        }
    }
}

private struct Market {
    let country: String
    let legalName: String
    let tradingName: String
    let contact: String
    let street: String
    let postalCode: String
    let city: String
    let vatID: String
    let registrationID: String
    let peppolScheme: String
    let peppolEndpoint: String
    let iban: String
    let bic: String
    let vatRate: Decimal

    static func forRegion(_ region: String?) -> Market {
        all.first { $0.country == region } ?? all[0]
    }

    func seller() -> Party {
        Party(
            id: "demo-seller", legalName: legalName, tradingName: tradingName, contactName: contact,
            email: "hello@\(tradingName.lowercased().filter { $0.isLetter }).example", phone: "",
            address: PostalAddress(line1: street, city: city, postalCode: postalCode, countryCode: country),
            vatID: vatID, legalRegistrationID: registrationID,
            peppolEndpointID: peppolEndpoint, peppolSchemeID: peppolScheme)
    }

    func paymentMeans() -> PaymentMeans {
        PaymentMeans(method: .creditTransfer, iban: iban, bic: bic, accountName: legalName)
    }

    static let all: [Market] = [
        Market(country: "DE", legalName: "Lindenhof Gestaltung GmbH", tradingName: "Lindenhof", contact: "Mara Hoffmann",
               street: "Sophienstraße 14", postalCode: "10178", city: "Berlin", vatID: "DE318204775",
               registrationID: "HRB 204118", peppolScheme: "9930", peppolEndpoint: "DE318204775",
               iban: "DE89 3704 0044 0532 0130 00", bic: "COBADEFFXXX", vatRate: 19),
        Market(country: "FR", legalName: "Studio Lumen EURL", tradingName: "Studio Lumen", contact: "Hélène Marchand",
               street: "8 rue des Tanneurs", postalCode: "69002", city: "Lyon", vatID: "FR27552081317",
               registrationID: "552 081 317", peppolScheme: "0009", peppolEndpoint: "55208131700021",
               iban: "FR76 3000 6000 0112 3456 7890 189", bic: "AGRIFRPP", vatRate: 20),
        Market(country: "IT", legalName: "Officina Pixel S.r.l.s.", tradingName: "Officina Pixel", contact: "Matteo Greco",
               street: "Via dei Mille 21", postalCode: "40121", city: "Bologna", vatID: "IT04817520968",
               registrationID: "BO-1482207", peppolScheme: "0211", peppolEndpoint: "IT04817520968",
               iban: "IT60 X054 2811 1010 0000 0123 456", bic: "BCITITMM", vatRate: 22),
        Market(country: "ES", legalName: "Taller Nómada S.L.", tradingName: "Taller Nómada", contact: "Lucía Navarro",
               street: "Calle de Alcalá 120", postalCode: "28009", city: "Madrid", vatID: "ESB84522017",
               registrationID: "B84522017", peppolScheme: "9920", peppolEndpoint: "ESB84522017",
               iban: "ES91 2100 0418 4502 0005 1332", bic: "CAIXESBB", vatRate: 21),
        Market(country: "NL", legalName: "Studio Kade B.V.", tradingName: "Studio Kade", contact: "Sanne de Vries",
               street: "Prinsengracht 233", postalCode: "1015 DT", city: "Amsterdam", vatID: "NL862514093B01",
               registrationID: "68251409", peppolScheme: "0106", peppolEndpoint: "68251409",
               iban: "NL91 ABNA 0417 1643 00", bic: "ABNANL2A", vatRate: 21),
        Market(country: "PL", legalName: "Pracownia Zorza Sp. z o.o.", tradingName: "Pracownia Zorza", contact: "Agnieszka Wrona",
               street: "ul. Piękna 24/26", postalCode: "00-549", city: "Warszawa", vatID: "PL5252871309",
               registrationID: "0000481562", peppolScheme: "9945", peppolEndpoint: "5252871309",
               iban: "PL61 1090 1014 0000 0712 1981 2874", bic: "WBKPPLPP", vatRate: 23),
        Market(country: "FI", legalName: "Kelo Design Oy", tradingName: "Kelo Design", contact: "Aino Virtanen",
               street: "Annankatu 31", postalCode: "00100", city: "Helsinki", vatID: "FI28471935",
               registrationID: "2847193-5", peppolScheme: "0216", peppolEndpoint: "003728471935",
               iban: "FI21 1234 5600 0007 85", bic: "NDEAFIHH", vatRate: 25.5),
        Market(country: "GB", legalName: "Fernhill Creative Ltd", tradingName: "Fernhill Creative", contact: "Imogen Clarke",
               street: "14 Queen Square", postalCode: "BS1 4NT", city: "Bristol", vatID: "GB284716103",
               registrationID: "09481527", peppolScheme: "0088", peppolEndpoint: "5060000000017",
               iban: "GB29 NWBK 6016 1331 9268 19", bic: "NWBKGB2L", vatRate: 20),
    ]
}

private enum ClientBook {
    static func all() -> [Party] {
        [
            party("demo-nordlicht", "Nordlicht GmbH", "Lena Brandt", "Friedrichstraße 100", "10117", "Berlin", "DE", "DE813592047", "9930", "DE813592047"),
            party("demo-montclair", "Atelier Montclair SAS", "Camille Roux", "12 cours de l'Intendance", "33000", "Bordeaux", "FR", "FR58402117586", "0009", "40211758600027"),
            party("demo-verdelago", "Studio Verdelago S.r.l.", "Giulia Ferrante", "Via Torino 48", "20123", "Milano", "IT", "IT07318490156", "0211", "IT07318490156"),
            party("demo-casamarea", "Casa Marea Hostelería S.L.", "Marta Ibáñez", "Calle Colón 17", "46004", "Valencia", "ES", "ESB97135820", "", ""),
            party("demo-linden", "Van der Linden Bouw B.V.", "Joost van der Linden", "Coolsingel 63", "3012 AC", "Rotterdam", "NL", "NL851647329B01", "0106", "24367518"),
            party("demo-gdansk", "Gdańska Pracownia Wzornictwa Sp. z o.o.", "Katarzyna Zielińska", "ul. Długa 47/49", "80-831", "Gdańsk", "PL", "PL5832014476", "", ""),
            party("demo-saimaa", "Saimaa Ventures Oy", "Mikko Laine", "Kauppakatu 3", "33100", "Tampere", "FI", "FI31652049", "0216", "003731652049"),
            party("demo-brightwater", "Brightwater Design Ltd", "Oliver Hayes", "22 Corn Street", "BS1 1HT", "Bristol", "GB", "GB318294760", "", ""),
            party("demo-vallombrosa", "Associazione Culturale Fondazione Vallombrosa per le Arti Applicate", "Chiara Bellini", "Via dei Servi 33", "50122", "Firenze", "IT", "IT94027510488", "", ""),
            party("demo-koskinen", "Anneli Koskinen", "", "Mariankatu 9", "00170", "Helsinki", "FI", "", "", ""),
            party("demo-lisboa", "Lisboa Leve Estúdio, Lda.", "Inês Carvalho", "Rua da Prata 112", "1100-420", "Lisboa", "PT", "PT509246813", "", ""),
            party("demo-polar", "Polar Mobile Oy", "Eero Salo", "Hämeenkatu 8", "20100", "Turku", "FI", "FI24681357", "0216", "003724681357"),
        ]
    }

    private static func party(
        _ id: String, _ name: String, _ contact: String, _ street: String, _ postal: String, _ city: String,
        _ country: String, _ vat: String, _ scheme: String, _ endpoint: String
    ) -> Party {
        let slug = name.lowercased().filter { $0.isLetter }.prefix(14)
        return Party(
            id: id, legalName: name, contactName: contact, email: "accounts@\(slug).example",
            address: PostalAddress(line1: street, city: city, postalCode: postal, countryCode: country),
            vatID: vat, peppolEndpointID: endpoint, peppolSchemeID: scheme)
    }
}

private struct Drafter {
    static let firstInvoiceNumber = 41
    static let firstEstimateNumber = 7

    let today: CalendarDate
    let seller: Party
    let market: Market
    let currency: Currency
    let pricing: Pricing

    private struct Job {
        let number: Int
        let type: DocumentType
        let status: DocumentStatus
        let client: String
        let issuedDaysAgo: Int
        let termDays: Int
        let work: [Work]
        let reference: String
        let prepaidShare: Decimal
    }

    private struct Work {
        let name: String
        let details: String
        let quantity: Decimal
        let unit: UnitCode
        let euros: Decimal
        let discount: Decimal
    }

    private static func work(_ name: String, _ details: String, _ quantity: Decimal, _ unit: UnitCode, _ euros: Decimal, discount: Decimal = 0) -> Work {
        Work(name: name, details: details, quantity: quantity, unit: unit, euros: euros, discount: discount)
    }

    private var jobs: [Job] {
        [
            Job(number: 41, type: .invoice, status: .paid, client: "demo-saimaa", issuedDaysAgo: 62, termDays: 14, work: [
                Self.work("Brand identity design", "Logo, type system, guidelines", 32, .hour, 95),
                Self.work("Landing page build", "Responsive, 4 sections", 1, .lumpSum, 2400, discount: 10),
            ], reference: "PO-SAIMAA-04", prepaidShare: 0),
            Job(number: 42, type: .invoice, status: .paid, client: "demo-nordlicht", issuedDaysAgo: 55, termDays: 30, work: [
                Self.work("iOS development", "Sprint 12", 56, .hour, 110),
                Self.work("Code review", "Release candidate", 6, .hour, 110),
            ], reference: "REF-NORDLICHT-22", prepaidShare: 0),
            Job(number: 43, type: .invoice, status: .paid, client: "demo-verdelago", issuedDaysAgo: 41, termDays: 14, work: [
                Self.work("Interface design", "Booking flow, 14 screens", 3, .day, 780),
            ], reference: "VRD-0412", prepaidShare: 0),
            Job(number: 44, type: .invoice, status: .overdue, client: "demo-linden", issuedDaysAgo: 33, termDays: 14, work: [
                Self.work("Site photography", "Two days on location", 2, .day, 640),
                Self.work("Image retouching", "40 selects", 40, .piece, 18),
                Self.work("Licence, regional print", "12 months", 1, .lumpSum, 350),
            ], reference: "VDL-2291", prepaidShare: 0),
            Job(number: 45, type: .invoice, status: .overdue, client: "demo-vallombrosa", issuedDaysAgo: 29, termDays: 14, work: [
                Self.work("Exhibition catalogue layout", "96 pages", 1, .lumpSum, 3200),
                Self.work("Cover illustration", "", 1, .piece, 450),
            ], reference: "", prepaidShare: 0),
            Job(number: 46, type: .invoice, status: .sent, client: "demo-montclair", issuedDaysAgo: 12, termDays: 30, work: [
                Self.work("Product photography", "Autumn range", 3, .day, 720),
                Self.work("Art direction", "On set", 8, .hour, 85),
            ], reference: "AM-PO-7718", prepaidShare: 0),
            Job(number: 47, type: .invoice, status: .viewed, client: "demo-brightwater", issuedDaysAgo: 9, termDays: 14, work: [
                Self.work("UX audit", "Heuristic review, 3 flows", 1, .lumpSum, 1800),
                Self.work("Prototype in Figma", "Clickable, 12 screens", 14, .hour, 95),
            ], reference: "BW-310", prepaidShare: 0),
            Job(number: 48, type: .invoice, status: .sent, client: "demo-casamarea", issuedDaysAgo: 6, termDays: 14, work: [
                Self.work("Menu and signage design", "Bilingual", 1, .lumpSum, 1250),
                Self.work("Printer liaison", "", 3, .hour, 70),
            ], reference: "CM-2026-31", prepaidShare: 0),
            Job(number: 49, type: .invoice, status: .draft, client: "demo-gdansk", issuedDaysAgo: 0, termDays: 30, work: [
                Self.work("Packaging concept", "Three directions", 1, .lumpSum, 2100),
                Self.work("Dieline preparation", "", 5, .hour, 75),
            ], reference: "", prepaidShare: 0),
            Job(number: 50, type: .invoice, status: .draft, client: "demo-lisboa", issuedDaysAgo: 1, termDays: 14, work: [
                Self.work("Motion graphics", "Opening title, 20 s", 1, .lumpSum, 1900),
                Self.work("Sound licence", "", 1, .piece, 120),
            ], reference: "LL-0099", prepaidShare: 0),
            Job(number: 51, type: .invoice, status: .partiallyPaid, client: "demo-nordlicht", issuedDaysAgo: 20, termDays: 30, work: [
                Self.work("iOS development", "Sprint 14", 60, .hour, 110),
            ], reference: "REF-NORDLICHT-31", prepaidShare: 0.4),
            Job(number: 52, type: .invoice, status: .paid, client: "demo-gdansk", issuedDaysAgo: 75, termDays: 14, work: [
                Self.work("Brand refresh", "Palette, typography", 24, .hour, 90),
            ], reference: "GP-114", prepaidShare: 0),
            Job(number: 53, type: .invoice, status: .paid, client: "demo-montclair", issuedDaysAgo: 90, termDays: 30, work: [
                Self.work("Photo retainer", "Month 1 of 3", 1, .month, 1500),
            ], reference: "AM-PO-7402", prepaidShare: 0),
            Job(number: 7, type: .estimate, status: .draft, client: "demo-brightwater", issuedDaysAgo: 1, termDays: 14, work: [
                Self.work("Design system audit", "Components and tokens", 1, .lumpSum, 2600),
                Self.work("Workshop facilitation", "Two half days", 2, .day, 720),
            ], reference: "", prepaidShare: 0),
            Job(number: 8, type: .estimate, status: .sent, client: "demo-lisboa", issuedDaysAgo: 4, termDays: 14, work: [
                Self.work("Campaign key visuals", "Five formats", 1, .lumpSum, 3400),
            ], reference: "", prepaidShare: 0),
            Job(number: 9, type: .estimate, status: .accepted, client: "demo-saimaa", issuedDaysAgo: 16, termDays: 14, work: [
                Self.work("App store assets", "Screenshots, 12 locales", 1, .lumpSum, 2800),
                Self.work("Icon variants", "", 4, .piece, 220),
            ], reference: "", prepaidShare: 0),
            Job(number: 10, type: .estimate, status: .declined, client: "demo-casamarea", issuedDaysAgo: 22, termDays: 14, work: [
                Self.work("Website redesign", "Ten pages, CMS", 1, .lumpSum, 5200),
            ], reference: "", prepaidShare: 0),
        ]
    }

    var invoiceCount: Int { jobs.filter { $0.type == .invoice }.count }
    var estimateCount: Int { jobs.filter { $0.type == .estimate }.count }

    func documents(clients: [Party]) -> [Invoice] {
        jobs.compactMap { job in
            guard let buyer = clients.first(where: { $0.id == job.client }) else { return nil }
            return document(for: job, buyer: buyer)
        }
    }

    private func document(for job: Job, buyer: Party) -> Invoice {
        let issued = today.adding(days: -job.issuedDaysAgo)
        let tax = taxTreatment(for: buyer)
        let prefix = job.type == .invoice ? "INV" : "EST"
        var invoice = Invoice(
            id: "demo-\(prefix.lowercased())-\(job.number)",
            type: job.type,
            status: job.status,
            number: String(format: "%@-%04d-%04d", prefix, today.year, job.number),
            issueDate: issued,
            dueDate: issued.adding(days: job.termDays),
            currency: currency,
            seller: seller,
            buyer: buyer,
            lines: job.work.enumerated().map { index, work in
                LineItem(
                    id: "l\(index + 1)", name: work.name, details: work.details, quantity: work.quantity, unit: work.unit,
                    unitPrice: pricing.price(work.euros), discountPercent: work.discount,
                    vatCategory: tax.category, vatRatePercent: tax.rate)
            },
            paymentMeans: market.paymentMeans(),
            paymentTerms: job.type == .invoice ? "Net \(job.termDays) days." : "Estimate valid for \(job.termDays) days.",
            note: tax.note,
            buyerReference: job.reference)
        if job.prepaidShare > 0 {
            let payable = invoice.totals().summary.payableAmount.minorUnits
            invoice.prepaidMinorUnits = NSDecimalNumber(decimal: Decimal(payable) * job.prepaidShare).intValue
        }
        return invoice
    }

    private struct TaxTreatment {
        let category: VATCategory
        let rate: Decimal
        let note: String
    }

    private func taxTreatment(for buyer: Party) -> TaxTreatment {
        let sameCountry = buyer.address.countryCode == seller.address.countryCode
        if sameCountry || !buyer.hasVATID {
            return TaxTreatment(category: .standard, rate: market.vatRate, note: "")
        }
        if Self.euMembers.contains(seller.address.countryCode), Self.euMembers.contains(buyer.address.countryCode) {
            return TaxTreatment(category: .intraCommunity, rate: 0, note: "VAT reverse charged, Article 196 of Directive 2006/112/EC.")
        }
        return TaxTreatment(category: .outsideScope, rate: 0, note: "Services outside the scope of EU VAT.")
    }

    private static let euMembers: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE",
        "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
    ]
}
#endif

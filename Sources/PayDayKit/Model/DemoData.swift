import Foundation

/// Canonical sample data. Seeds a first-run example invoice (App Review 2.1
/// completeness) and backs unit tests and previews with a realistic document
/// that exercises standard VAT, an intra-community line, and a discount.
public enum DemoData {
    public static func sampleSeller() -> Party {
        Party(
            id: "seller-demo",
            legalName: "Aurora Studio Oy",
            tradingName: "Aurora Studio",
            contactName: "Marcus Ziadé",
            email: "billing@aurorastudio.example",
            phone: "+358 40 123 4567",
            address: PostalAddress(
                line1: "Mannerheimintie 12",
                city: "Helsinki",
                postalCode: "00100",
                countryCode: "FI"),
            vatID: "FI12345678",
            legalRegistrationID: "1234567-8",
            peppolEndpointID: "0037:12345678",
            peppolSchemeID: "0037")
    }

    public static func sampleBuyer() -> Party {
        Party(
            id: "buyer-demo",
            legalName: "Nordlicht GmbH",
            contactName: "Lena Brandt",
            email: "ap@nordlicht.example",
            address: PostalAddress(
                line1: "Friedrichstraße 100",
                city: "Berlin",
                postalCode: "10117",
                countryCode: "DE"),
            vatID: "DE123456789",
            peppolEndpointID: "9930:DE123456789",
            peppolSchemeID: "9930")
    }

    /// A domestic (Finnish) invoice with standard 25.5% VAT and a discounted line.
    public static func sampleInvoice() -> Invoice {
        Invoice(
            id: "doc-demo-1",
            type: .invoice,
            status: .sent,
            number: "INV-2026-0007",
            issueDate: CalendarDate(year: 2026, month: 6, day: 1),
            dueDate: CalendarDate(year: 2026, month: 6, day: 15),
            currency: .eur,
            seller: sampleSeller(),
            buyer: Party(
                id: "buyer-domestic",
                legalName: "Saimaa Ventures Oy",
                email: "laskut@saimaa.example",
                address: PostalAddress(line1: "Kauppakatu 3", city: "Tampere", postalCode: "33100", countryCode: "FI"),
                vatID: "FI87654321"),
            lines: [
                LineItem(
                    id: "l1", name: "Brand identity design", details: "Logo, type system, guidelines",
                    quantity: 32, unit: .hour, unitPrice: 95, vatCategory: .standard, vatRatePercent: 25.5),
                LineItem(
                    id: "l2", name: "Landing page build", details: "Responsive, 4 sections",
                    quantity: 1, unit: .lumpSum, unitPrice: 2400, discountPercent: 10,
                    vatCategory: .standard, vatRatePercent: 25.5),
            ],
            paymentMeans: PaymentMeans(
                method: .creditTransfer, iban: "FI21 1234 5600 0007 85", bic: "OKOYFIHH",
                accountName: "Aurora Studio Oy", remittanceReference: "RF18 0007"),
            paymentTerms: "Net 14 days. 8% annual interest on overdue amounts.",
            note: "Thank you for working with Aurora Studio.",
            buyerReference: "PO-SAIMAA-2026-04")
    }

    /// A cross-border B2B invoice using the intra-community reverse-charge
    /// category (0% VAT, both parties VAT-registered) — the EU compliance case.
    public static func sampleIntraCommunityInvoice() -> Invoice {
        Invoice(
            id: "doc-demo-2",
            type: .invoice,
            status: .draft,
            number: "INV-2026-0008",
            issueDate: CalendarDate(year: 2026, month: 6, day: 5),
            dueDate: CalendarDate(year: 2026, month: 7, day: 5),
            currency: .eur,
            seller: sampleSeller(),
            buyer: sampleBuyer(),
            lines: [
                LineItem(
                    id: "l1", name: "iOS development", details: "Sprint 14",
                    quantity: 60, unit: .hour, unitPrice: 110,
                    vatCategory: .intraCommunity, vatRatePercent: 0),
            ],
            paymentMeans: PaymentMeans(
                method: .creditTransfer, iban: "FI21 1234 5600 0007 85", bic: "OKOYFIHH",
                accountName: "Aurora Studio Oy"),
            paymentTerms: "Net 30 days.",
            note: "VAT reverse charged — Article 196 VAT Directive 2006/112/EC.",
            buyerReference: "REF-NORDLICHT-22")
    }
}

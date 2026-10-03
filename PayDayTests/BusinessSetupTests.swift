import Testing
import Foundation
@testable import PayDay
import PayDayKit

/// The example business seeded on first launch must never read as the user's
/// own, and must never survive onto a document the user delivers.
@Suite("Business setup")
@MainActor
struct BusinessSetupTests {
    @Test("The seeded profile is the demo and is not configured")
    func seededIsDemo() {
        let demo = BusinessProfile.demo()
        #expect(demo.isDemo)
        #expect(!demo.isConfigured)
    }

    @Test("An existing install's demo profile, re-saved untouched through Settings, is still the demo")
    func resavedDemoIsDemo() {
        var resaved = BusinessProfile.demo()
        resaved.paymentMeans.iban = resaved.paymentMeans.normalizedIBAN
        resaved.seller.vatID = resaved.seller.vatID.normalizedVATID
        resaved.defaultVATRatePercent = 24
        #expect(resaved.isDemo)
        #expect(!resaved.isConfigured)
    }

    @Test("Editing the name or the IBAN alone makes it the user's business")
    func partialEditIsConfigured() {
        var renamed = BusinessProfile.demo()
        renamed.seller.legalName = "Studio Lumen BV"
        #expect(renamed.isConfigured)
        var rebanked = BusinessProfile.demo()
        rebanked.paymentMeans.iban = "BE68 5390 0754 7034"
        #expect(rebanked.isConfigured)
    }

    @Test("A blank profile is neither the demo nor configured")
    func blankProfile() {
        #expect(!BusinessProfile().isDemo)
        #expect(!BusinessProfile().isConfigured)
    }

    @Test("Starting in a country takes its currency, VAT rate and e-invoice profile")
    func regionalStart() {
        let poland = BusinessProfile.starting(in: "pl")
        #expect(poland.seller.address.countryCode == "PL")
        #expect(poland.defaultCurrencyCode == "PLN")
        #expect(poland.defaultVATRatePercent == 23)
        #expect(poland.defaultEInvoiceProfile == .en16931)
        let unknown = BusinessProfile.starting(in: "US")
        #expect(unknown.seller.address.countryCode == "US")
        #expect(unknown.defaultCurrencyCode == BusinessProfile().defaultCurrencyCode)
    }

    @Test("A sample or seller-less document is held back; the user's own goes out")
    func deliveryGate() {
        #expect(!BusinessSetupGate.canDeliver(DemoData.sampleInvoice()))
        var blank = DemoData.sampleInvoice()
        blank.seller = Party(id: "business", legalName: "  ")
        #expect(!BusinessSetupGate.canDeliver(blank))
        var own = DemoData.sampleInvoice()
        own.seller.legalName = "Studio Lumen BV"
        #expect(BusinessSetupGate.canDeliver(own))
    }

    @Test("Reissuing replaces the example seller and bank account and drops its remittance reference")
    func reissueSample() {
        var profile = BusinessProfile.starting(in: "BE")
        profile.seller.legalName = "Studio Lumen BV"
        profile.paymentMeans = PaymentMeans(iban: "BE68539007547034", accountName: "Studio Lumen BV")
        let reissued = BusinessSetupGate.reissue(DemoData.sampleInvoice(), as: profile)
        #expect(reissued.seller == profile.seller)
        #expect(reissued.paymentMeans.iban == "BE68539007547034")
        #expect(reissued.paymentMeans.remittanceReference.isEmpty)
        #expect(reissued.lines == DemoData.sampleInvoice().lines)
        #expect(BusinessSetupGate.canDeliver(reissued))
    }

    @Test("Reissuing the user's own document keeps its remittance reference")
    func reissueOwn() {
        var invoice = DemoData.sampleInvoice()
        invoice.seller = Party(id: "business", legalName: "Old Name Oy")
        invoice.paymentMeans.remittanceReference = "RF18 0042"
        var profile = BusinessProfile()
        profile.seller.legalName = "New Name Oy"
        #expect(BusinessSetupGate.reissue(invoice, as: profile).paymentMeans.remittanceReference == "RF18 0042")
    }
}

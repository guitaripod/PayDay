import Testing
import Foundation
@testable import PayDayKit

@Suite("Sample seller recognition")
struct SampleSellerTests {
    @Test("The seeded seller is recognised, including after an untouched re-save")
    func untouchedIsSample() {
        #expect(DemoData.isSampleSeller(DemoData.sampleSeller()))
        var resaved = DemoData.sampleSeller()
        resaved.id = "business"
        resaved.vatID = " fi 1234 5678 "
        resaved.legalName = "Aurora Studio Oy "
        resaved.email = ""
        #expect(DemoData.isSampleSeller(resaved))
    }

    @Test("Changing any identifying field makes it the user's own business",
          arguments: ["legalName", "vatID", "legalRegistrationID", "peppolEndpointID", "peppolSchemeID"])
    func editedIsNotSample(_ field: String) {
        var party = DemoData.sampleSeller()
        switch field {
        case "legalName": party.legalName = "Mine"
        case "vatID": party.vatID = "BE0123456789"
        case "legalRegistrationID": party.legalRegistrationID = "0123456789"
        case "peppolEndpointID": party.peppolEndpointID = "0123456789"
        default: party.peppolSchemeID = "0208"
        }
        #expect(!DemoData.isSampleSeller(party))
    }

    @Test("A changed address is the user's own business")
    func editedAddress() {
        var party = DemoData.sampleSeller()
        party.address.countryCode = "BE"
        #expect(!DemoData.isSampleSeller(party))
    }

    @Test("A blank seller is not the sample")
    func blankIsNotSample() {
        #expect(!DemoData.isSampleSeller(Party(id: "business", legalName: "")))
    }
}

@Suite("Regional defaults")
struct RegionalDefaultsTests {
    @Test("Finland bills in euro at 25.5 % with the EN 16931 profile")
    func finland() {
        let fi = RegionalDefaults.forCountry(" fi ")
        #expect(fi?.countryCode == "FI")
        #expect(fi?.currencyCode == "EUR")
        #expect(fi?.standardVATRatePercent == Decimal(string: "25.5"))
        #expect(fi?.eInvoiceProfile == .en16931)
    }

    @Test("Non-euro member states keep their own currency")
    func nonEuro() {
        #expect(RegionalDefaults.forCountry("PL")?.currencyCode == "PLN")
        #expect(RegionalDefaults.forCountry("SE")?.currencyCode == "SEK")
        #expect(RegionalDefaults.forCountry("HU")?.standardVATRatePercent == 27)
    }

    @Test("Every EU member state and every mandate country has defaults")
    func coversMandates() {
        for code in EInvoicingMandates.unionMemberStates.union(EInvoicingMandates.catalogue.keys) {
            #expect(RegionalDefaults.forCountry(code) != nil, "missing \(code)")
        }
        #expect(RegionalDefaults.supportedCountryCodes == RegionalDefaults.supportedCountryCodes.sorted())
    }

    @Test("Countries outside the table have none")
    func unknown() {
        #expect(RegionalDefaults.forCountry("US") == nil)
        #expect(RegionalDefaults.forCountry("") == nil)
    }
}

import Testing
import Foundation
@testable import PayDayKit

@Suite("Peppol participant identifiers (Finnish OVT)")
struct PeppolParticipantTests {
    @Test("OVT derived from a Finnish business ID keeps the fixed 0037 prefix")
    func ovtFromBusinessID() {
        #expect(PeppolParticipant.finnishOVT(fromBusinessID: "3559549-7")
            == PeppolID(schemeID: "0216", endpointID: "003735595497"))
        #expect(PeppolParticipant.finnishOVT(fromBusinessID: "1234567-8")
            == PeppolID(schemeID: "0216", endpointID: "003712345678"))
    }

    @Test("OVT derives equally from a Finnish VAT number (same 8 digits)")
    func ovtFromVAT() {
        #expect(PeppolParticipant.finnishOVT(fromBusinessID: "FI35595497")
            == PeppolID(schemeID: "0216", endpointID: "003735595497"))
    }

    @Test("OVT accepts an optional org-unit suffix, uppercased")
    func ovtWithSuffix() {
        #expect(PeppolParticipant.finnishOVT(fromBusinessID: "3559549-7", suffix: "ab1")
            == PeppolID(schemeID: "0216", endpointID: "003735595497AB1"))
    }

    @Test("OVT derivation refuses anything but exactly 8 business-ID digits")
    func ovtRejectsMalformed() {
        #expect(PeppolParticipant.finnishOVT(fromBusinessID: "123") == nil)
        #expect(PeppolParticipant.finnishOVT(fromBusinessID: "003735595497") == nil)
        #expect(PeppolParticipant.finnishOVT(fromBusinessID: "") == nil)
    }

    @Test("Normalisation upgrades 0037 OVT to 0216 without touching the value")
    func normalizesLegacyOVT() {
        #expect(PeppolParticipant.normalized(PeppolID(schemeID: "0037", endpointID: "003735595497"))
            == PeppolID(schemeID: "0216", endpointID: "003735595497"))
    }

    @Test("Normalisation never guesses: non-OVT and foreign values pass through")
    func normalizationIsConservative() {
        #expect(PeppolParticipant.normalized(PeppolID(schemeID: "0037", endpointID: "12345678"))
            == PeppolID(schemeID: "0037", endpointID: "12345678"))
        #expect(PeppolParticipant.normalized(PeppolID(schemeID: "9930", endpointID: "DE123456789"))
            == PeppolID(schemeID: "9930", endpointID: "DE123456789"))
        #expect(PeppolParticipant.normalized(PeppolID(schemeID: "0216", endpointID: "003735595497"))
            == PeppolID(schemeID: "0216", endpointID: "003735595497"))
    }

    @Test("A valid 0216 OVT is recognised; malformed values are not")
    func ovtValidity() {
        #expect(PeppolParticipant.isValidFinnishOVT("003735595497"))
        #expect(PeppolParticipant.isValidFinnishOVT("003735595497TST01"))
        #expect(!PeppolParticipant.isValidFinnishOVT("35595497"))
        #expect(!PeppolParticipant.isValidFinnishOVT("00373559549"))
        #expect(!PeppolParticipant.isValidFinnishOVT("003735595497TOOLONG"))
    }

    @Test("Advisory upgrades a legacy 0037 scheme on a Finnish party")
    func advisoryUpgradesLegacy() {
        let a = PeppolParticipant.advisory(
            schemeID: "0037", endpointID: "003735595497",
            countryCode: "FI", vatID: "FI35595497", businessID: "3559549-7")
        #expect(a?.level == .warning)
        #expect(a?.suggestion == PeppolID(schemeID: "0216", endpointID: "003735595497"))
    }

    @Test("Advisory derives 0216 from a 0213 VAT-scheme Finnish participant")
    func advisoryDerivesFromVATScheme() {
        let a = PeppolParticipant.advisory(
            schemeID: "0213", endpointID: "FI35595497",
            countryCode: "FI", vatID: "FI35595497", businessID: "")
        #expect(a?.suggestion == PeppolID(schemeID: "0216", endpointID: "003735595497"))
    }

    @Test("Advisory suggests an OVT for a Finnish party with no Peppol id yet")
    func advisorySuggestsForEmpty() {
        let a = PeppolParticipant.advisory(
            schemeID: "", endpointID: "",
            countryCode: "FI", vatID: "FI35595497", businessID: "")
        #expect(a?.level == .info)
        #expect(a?.suggestion == PeppolID(schemeID: "0216", endpointID: "003735595497"))
    }

    @Test("Advisory is silent when the Finnish OVT is already correct")
    func advisorySilentWhenValid() {
        let a = PeppolParticipant.advisory(
            schemeID: "0216", endpointID: "003735595497",
            countryCode: "FI", vatID: "FI35595497", businessID: "3559549-7")
        #expect(a == nil)
    }

    @Test("Advisory leaves a well-formed non-Finnish identifier alone")
    func advisoryIgnoresValidForeign() {
        let a = PeppolParticipant.advisory(
            schemeID: "9930", endpointID: "DE123456789",
            countryCode: "DE", vatID: "DE123456789", businessID: "")
        #expect(a == nil)
    }

    @Test("PeppolID parses the scheme:value form used in the UI")
    func parsesWireForm() {
        #expect(PeppolID(parsing: "0216:003735595497")
            == PeppolID(schemeID: "0216", endpointID: "003735595497"))
        #expect(PeppolID(parsing: "  0216 : 003735595497 ")
            == PeppolID(schemeID: "0216", endpointID: "003735595497"))
        #expect(PeppolID(parsing: "nocolon").isEmpty)
    }
}

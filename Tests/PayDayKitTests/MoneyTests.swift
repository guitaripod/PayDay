import Testing
import Foundation
@testable import PayDayKit

@Suite("Money & Currency")
struct MoneyTests {
    @Test("Canonical decimal string honours minor-unit digits")
    func canonicalString() {
        #expect(Money(minorUnits: 0, currency: .eur).canonicalString == "0.00")
        #expect(Money(minorUnits: 5, currency: .eur).canonicalString == "0.05")
        #expect(Money(minorUnits: 150, currency: .eur).canonicalString == "1.50")
        #expect(Money(minorUnits: 123456, currency: .eur).canonicalString == "1234.56")
        #expect(Money(minorUnits: -150, currency: .eur).canonicalString == "-1.50")
    }

    @Test("Zero-decimal and three-decimal currencies")
    func nonDefaultDigits() {
        let jpy = Currency("JPY")
        #expect(jpy.minorUnitDigits == 0)
        #expect(Money(minorUnits: 1235, currency: jpy).canonicalString == "1235")

        let bhd = Currency("BHD")
        #expect(bhd.minorUnitDigits == 3)
        #expect(Money(minorUnits: 1235, currency: bhd).canonicalString == "1.235")
    }

    @Test("Half-up rounding into minor units")
    func rounding() {
        #expect(Money(rounding: Decimal(string: "10.005")!, in: .eur).minorUnits == 1001)
        #expect(Money(rounding: Decimal(string: "10.004")!, in: .eur).minorUnits == 1000)
        #expect(Money(rounding: Decimal(string: "0.999")!, in: .eur).minorUnits == 100)
        #expect(Money(rounding: Decimal(string: "1234.56")!, in: Currency("JPY")).minorUnits == 1235)
    }

    @Test("Arithmetic stays in minor units")
    func arithmetic() {
        let a = Money(minorUnits: 304000, currency: .eur)
        let b = Money(minorUnits: 216000, currency: .eur)
        #expect((a + b).minorUnits == 520000)
        #expect((a - b).minorUnits == 88000)
        #expect(Money.sum([a, b, b], currency: .eur).minorUnits == 736000)
        #expect((-a).minorUnits == -304000)
    }

    @Test("Amount decimal round-trips")
    func amount() {
        #expect(Money(minorUnits: 652600, currency: .eur).amount == Decimal(string: "6526.00"))
    }
}

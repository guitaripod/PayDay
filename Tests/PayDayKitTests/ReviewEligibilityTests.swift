import Testing
import Foundation
@testable import PayDayKit

@Suite("Review prompt eligibility")
struct ReviewEligibilityTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func days(_ n: Double) -> TimeInterval { n * 86_400 }

    @Test("No ask before any delivery")
    func noAskBeforeFirstDelivery() {
        #expect(ReviewEligibility.shouldAsk(successCount: 0, askDates: [], successCountAtLastAsk: 0, now: now) == false)
    }

    @Test("Asks on the first delivery — rare and heavy, so it doesn't wait for a second")
    func asksOnFirstDelivery() {
        #expect(ReviewEligibility.shouldAsk(successCount: 1, askDates: [], successCountAtLastAsk: 0, now: now) == true)
    }

    @Test("No re-ask right after the first ask, even with more deliveries")
    func noReAskImmediatelyAfterFirstAsk() {
        let askDates = [now.addingTimeInterval(-days(1))]
        #expect(ReviewEligibility.shouldAsk(successCount: 5, askDates: askDates, successCountAtLastAsk: 1, now: now) == false)
    }

    @Test("No re-ask before 14 days, even with 3+ new deliveries")
    func noReAskBefore14Days() {
        let askDates = [now.addingTimeInterval(-days(10))]
        #expect(ReviewEligibility.shouldAsk(successCount: 5, askDates: askDates, successCountAtLastAsk: 1, now: now) == false)
    }

    @Test("No re-ask before 3 new deliveries, even after 14 days")
    func noReAskBefore3NewSuccesses() {
        let askDates = [now.addingTimeInterval(-days(20))]
        #expect(ReviewEligibility.shouldAsk(successCount: 3, askDates: askDates, successCountAtLastAsk: 1, now: now) == false)
    }

    @Test("Re-asks once both 14 days and 3 new deliveries have passed")
    func reAsksAfterBothConditions() {
        let askDates = [now.addingTimeInterval(-days(20))]
        #expect(ReviewEligibility.shouldAsk(successCount: 4, askDates: askDates, successCountAtLastAsk: 1, now: now) == true)
    }

    @Test("Never a 4th ask within a rolling 365 days")
    func neverA4thAskWithinRollingYear() {
        let askDates = [
            now.addingTimeInterval(-days(300)),
            now.addingTimeInterval(-days(200)),
            now.addingTimeInterval(-days(100)),
        ]
        #expect(ReviewEligibility.shouldAsk(successCount: 100, askDates: askDates, successCountAtLastAsk: 1, now: now) == false)
    }

    @Test("A 4th ask is allowed once the oldest of the three ages out of the window")
    func fourthAskAllowedOnceOldestAgesOut() {
        let askDates = [
            now.addingTimeInterval(-days(400)),
            now.addingTimeInterval(-days(200)),
            now.addingTimeInterval(-days(100)),
        ]
        #expect(ReviewEligibility.shouldAsk(successCount: 100, askDates: askDates, successCountAtLastAsk: 1, now: now) == true)
    }

    @Test("A rolling-year cap of exactly 2 recent asks still allows a 3rd")
    func capAllowsUpToThree() {
        let askDates = [
            now.addingTimeInterval(-days(200)),
            now.addingTimeInterval(-days(100)),
        ]
        #expect(ReviewEligibility.shouldAsk(successCount: 100, askDates: askDates, successCountAtLastAsk: 1, now: now) == true)
    }

    @Test("13 days since the last ask is not yet eligible")
    func thirteenDaysIsNotEnough() {
        let askDates = [now.addingTimeInterval(-days(13))]
        #expect(ReviewEligibility.shouldAsk(successCount: 4, askDates: askDates, successCountAtLastAsk: 1, now: now) == false)
    }

    @Test("Exactly 14 days since the last ask is eligible, with enough new successes")
    func fourteenDaysIsEnough() {
        let askDates = [now.addingTimeInterval(-days(14))]
        #expect(ReviewEligibility.shouldAsk(successCount: 4, askDates: askDates, successCountAtLastAsk: 1, now: now) == true)
    }

    @Test("2 new successes since the last ask is not yet enough, even long after 14 days")
    func twoNewSuccessesIsNotEnough() {
        let askDates = [now.addingTimeInterval(-days(30))]
        #expect(ReviewEligibility.shouldAsk(successCount: 3, askDates: askDates, successCountAtLastAsk: 1, now: now) == false)
    }

    @Test("Exactly 3 new successes since the last ask is enough, once 14 days have passed")
    func threeNewSuccessesIsEnough() {
        let askDates = [now.addingTimeInterval(-days(30))]
        #expect(ReviewEligibility.shouldAsk(successCount: 4, askDates: askDates, successCountAtLastAsk: 1, now: now) == true)
    }

    @Test("An ask exactly 365 days old has just aged out of the rolling window")
    func askAgesOutAtExactlyOneYear() {
        let askDates = [
            now.addingTimeInterval(-days(365)),
            now.addingTimeInterval(-days(200)),
            now.addingTimeInterval(-days(100)),
        ]
        #expect(ReviewEligibility.shouldAsk(successCount: 100, askDates: askDates, successCountAtLastAsk: 1, now: now) == true)
    }
}

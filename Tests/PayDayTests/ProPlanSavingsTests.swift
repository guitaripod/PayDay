import Foundation
import Testing
@testable import PayDay

struct ProPlanSavingsTests {
    private func plan(_ period: ProPlan.Period, _ price: Decimal) -> ProPlan {
        ProPlan(id: "\(period)", localizedPrice: "\(price)", price: price, period: period, trialDays: nil, trialEligible: false)
    }

    @Test func theAnnualPlanSavesAgainstTwelveMonthsRoundedDown() {
        #expect(ProPlan.annualSavingsPercent(in: [plan(.annual, 39.99), plan(.monthly, 4.99)]) == 33)
        #expect(ProPlan.annualSavingsPercent(in: [plan(.monthly, 9.99), plan(.annual, 59.99)]) == 49)
    }

    @Test func noSavingsWithoutBothPlansOrWhenTheYearCostsMore() {
        #expect(ProPlan.annualSavingsPercent(in: [plan(.annual, 39.99)]) == nil)
        #expect(ProPlan.annualSavingsPercent(in: [plan(.annual, 70), plan(.monthly, 4.99)]) == nil)
    }
}

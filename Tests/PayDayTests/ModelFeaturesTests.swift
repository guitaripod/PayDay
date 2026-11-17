import AICreditsCore
import MidgarCore
import PayDayCore
import Testing
@testable import PayDay

struct ModelFeaturesTests {
    @Test func everyModelEntryPointHidesWhileTheRegionRefusesModels() {
        let refused = ModelFeatures(modelsAvailable: false)
        #expect(!refused.showsAIDrafting)
        #expect(!refused.showsLineItemDrafting)
        #expect(!refused.creditsCoverAIDrafting)
        #expect(!refused.showsReminderDrafting(for: overdueInvoice()))
    }

    @Test func everyModelEntryPointShowsWhereTheModelsWork() {
        let open = ModelFeatures(modelsAvailable: true)
        #expect(open.showsAIDrafting)
        #expect(open.showsLineItemDrafting)
        #expect(open.creditsCoverAIDrafting)
        #expect(open.showsReminderDrafting(for: overdueInvoice()))
    }

    @Test func aReminderNeedsAnOverdueInvoice() {
        var paid = DemoData.sampleInvoice()
        paid.status = .paid
        #expect(!ModelFeatures(modelsAvailable: true).showsReminderDrafting(for: paid))
    }

    @Test func aRefusalIsRecognizedFromEitherClient() {
        #expect(ModelRefusal.isRefusal(MidgarHTTPError.server(status: 451, code: "unavailable_in_region", message: "")))
        #expect(ModelRefusal.isRefusal(AICreditsError.server(code: "unavailable_in_region", message: "")))
        #expect(!ModelRefusal.isRefusal(MidgarHTTPError.server(status: 500, code: nil, message: "")))
        #expect(!ModelRefusal.isRefusal(AICreditsError.server(code: "rate_limited", message: "")))
        #expect(!ModelRefusal.isRefusal(AICreditsError.insufficientCredits(required: 1, available: 0)))
    }

    private func overdueInvoice() -> Invoice {
        var invoice = DemoData.sampleInvoice()
        invoice.status = .overdue
        return invoice
    }
}

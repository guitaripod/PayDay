import Testing
@testable import PayDayCore

struct PaymentReminderTests {
    private static let facts = ReminderFacts(client: "Linden Design Oy", invoiceNumber: "2026-044", amount: "1\u{00A0}240,00\u{00A0}€", dueDate: "27.10.2026")

    private static func reply(subject: String = "Reminder: invoice 2026-044", body: String) -> String {
        let escaped = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n")
        return #"{"subject":"\#(subject)","body":"\#(escaped)"}"#
    }

    private static let good = """
    Dear Linden Design Oy,

    This is a friendly reminder that invoice 2026-044 for 1 240,00 € was due on 27.10.2026 and is still open.
    Could you let me know when I can expect the payment?

    Kind regards,
    """

    @Test func theRequestIsTheToneAndTheFourFactsALineEach() {
        let odd = ReminderFacts(client: "Linden\nDesign  Oy", invoiceNumber: " 2026-044 ", amount: "1\u{202F}240,00\u{00A0}€", dueDate: "27.10.2026")
        #expect(odd == Self.facts)
        #expect(PaymentReminder.input(Self.facts, tone: .firm) == "Tone: firm\nClient: Linden Design Oy\nInvoice: 2026-044\nAmount: 1 240,00 €\nDue: 27.10.2026")
        #expect(ReminderTone.allCases.map(\.rawValue) == ["friendly", "firm", "final"])
    }

    @Test func aDraftThatStatesTheFactsIsTakenAndSigned() throws {
        let draft = try #require(PaymentReminder.draft(from: Self.reply(body: Self.good), facts: Self.facts, signature: "Aino Virtanen"))
        #expect(draft.subject == "Reminder: invoice 2026-044")
        #expect(draft.body.hasPrefix("Dear Linden Design Oy,\n\nThis is a friendly reminder"))
        #expect(draft.body.hasSuffix("Kind regards,\nAino Virtanen"))
        #expect(!draft.body.contains("\n\n\n"))
        let unsigned = try #require(PaymentReminder.draft(from: Self.reply(body: Self.good), facts: Self.facts))
        #expect(unsigned.body.hasSuffix("Kind regards,"))
    }

    @Test func theAmountMayComeBackWithOrdinaryOrUnbreakableSpaces() {
        let unbreakable = Self.good.replacingOccurrences(of: "1 240,00 €", with: "1\u{00A0}240,00\u{00A0}€")
        #expect(PaymentReminder.draft(from: Self.reply(body: unbreakable), facts: Self.facts) != nil)
    }

    @Test func aDraftThatAddsAFigureIsRefused() {
        let fee = Self.good.replacingOccurrences(of: "is still open.", with: "is still open. A late fee of 40 € now applies.")
        let interest = Self.good.replacingOccurrences(of: "is still open.", with: "is still open. Interest of 8% accrues.")
        let deadline = Self.good.replacingOccurrences(of: "is still open.", with: "is still open. Please pay within 7 days.")
        let otherAmount = Self.good.replacingOccurrences(of: "1 240,00 €", with: "1 420,00 €")
        let otherDate = Self.good.replacingOccurrences(of: "27.10.2026", with: "28.10.2026")
        for body in [fee, interest, deadline, otherAmount, otherDate] {
            #expect(PaymentReminder.draft(from: Self.reply(body: body), facts: Self.facts) == nil)
        }
        #expect(PaymentReminder.draft(from: Self.reply(subject: "Invoice 2026-044, second notice 2", body: Self.good), facts: Self.facts) == nil)
    }

    @Test func aDraftThatLeavesOutAFactOrLeavesAPlaceholderIsRefused() {
        let noNumber = Self.good.replacingOccurrences(of: "invoice 2026-044 ", with: "your invoice ")
        #expect(PaymentReminder.draft(from: Self.reply(subject: "Payment reminder", body: noNumber), facts: Self.facts) == nil)
        #expect(PaymentReminder.draft(from: Self.reply(body: Self.good.replacingOccurrences(of: "for 1 240,00 € ", with: "")), facts: Self.facts) == nil)
        #expect(PaymentReminder.draft(from: Self.reply(body: Self.good.replacingOccurrences(of: " was due on 27.10.2026 and", with: "")), facts: Self.facts) == nil)
        #expect(PaymentReminder.draft(from: Self.reply(body: Self.good + "\n[Your name]"), facts: Self.facts) == nil)
        #expect(PaymentReminder.draft(from: Self.reply(body: "Pay invoice 2026-044."), facts: Self.facts) == nil)
        #expect(PaymentReminder.draft(from: "Here is your reminder.", facts: Self.facts) == nil)
        #expect(PaymentReminder.draft(from: Self.reply(subject: "", body: Self.good), facts: Self.facts) == nil)
    }

    @Test func aSubjectTagAndChineseNumeralsInsideWordsAreNotAdditions() {
        let company = ReminderFacts(client: "晨光设计有限公司", invoiceNumber: "INV-2026-0142", amount: "¥9,800.00", dueDate: "2026年10月14日")
        let body = "晨光设计有限公司 您好：\n\n希望您一切顺利。这是关于发票 INV-2026-0142 的最后一次提醒，金额为 ¥9,800.00，付款截止日期为 2026年10月14日，目前仍未收到款项。请您尽快安排付款。\n\n顺祝商祺，"
        #expect(PaymentReminder.draft(from: Self.reply(subject: "【最后提醒】发票 INV-2026-0142", body: body), facts: company) != nil)
        #expect(PaymentReminder.draft(from: Self.reply(subject: "[最后提醒] 发票 INV-2026-0142", body: body), facts: company) != nil)
        for added in ["请在三天内付款。", "逾期将加收百分之五的滞纳金。", "另收五百元手续费。", "请于７日内付款。"] {
            let more = body.replacingOccurrences(of: "请您尽快安排付款。", with: added)
            #expect(PaymentReminder.draft(from: Self.reply(subject: "发票 INV-2026-0142", body: more), facts: company) == nil, "\(added)")
        }
        #expect(PaymentReminder.draft(from: Self.reply(subject: "发票 INV-2026-0142", body: body + "\n[您的姓名]"), facts: company) == nil)
        #expect(!PaymentReminder.statesACountInHanNumerals("最后一次提醒，统一处理，一切顺利"))
    }

    @Test func figuresAndBracketsInTheClientsOwnNameAreNotTakenForAdditions() {
        let studio = ReminderFacts(client: "Studio 54 [Berlin] GmbH", invoiceNumber: "44", amount: "€1,244.00", dueDate: "14 Oct 2026")
        let body = "Dear Studio 54 [Berlin] GmbH,\n\nInvoice 44 for €1,244.00 was due on 14 Oct 2026 and has not been paid yet. Please arrange payment.\n\nKind regards,"
        #expect(PaymentReminder.draft(from: Self.reply(subject: "Invoice 44 is overdue", body: body), facts: studio) != nil)
        let another = body.replacingOccurrences(of: "Please arrange payment.", with: "Please arrange payment by 21 Oct 2026.")
        #expect(PaymentReminder.draft(from: Self.reply(subject: "Invoice 44 is overdue", body: another), facts: studio) == nil)
    }
}

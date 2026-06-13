import Foundation

/// A single validation finding against the EN 16931 business rules. `rule` is
/// the EN 16931 / Peppol rule identifier (e.g. "BR-CO-15") so a user — or a
/// support log — can look up the exact requirement.
public struct ValidationIssue: Sendable, Equatable, Hashable, Codable, Identifiable {
    public enum Severity: String, Sendable, Equatable, Hashable, Codable {
        case error
        case warning
    }

    public var id: String { rule + ":" + message }
    public let severity: Severity
    public let rule: String
    public let message: String

    public init(severity: Severity, rule: String, message: String) {
        self.severity = severity
        self.rule = rule
        self.message = message
    }
}

/// Validates an invoice against the load-bearing EN 16931 business rules before
/// it can be issued as a compliant e-invoice. Errors block compliant output;
/// warnings are advisory. This is intentionally a curated subset of the full
/// rule set — the rules whose violation actually causes an access point or tax
/// authority to reject the document.
public enum InvoiceValidator {
    public static func validate(_ invoice: Invoice) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let totals = invoice.totals()

        func error(_ rule: String, _ message: String) {
            issues.append(ValidationIssue(severity: .error, rule: rule, message: message))
        }
        func warning(_ rule: String, _ message: String) {
            issues.append(ValidationIssue(severity: .warning, rule: rule, message: message))
        }

        if invoice.number.trimmed.isEmpty {
            error("BR-02", "An invoice must have an invoice number (BT-1).")
        }
        if invoice.seller.legalName.trimmed.isEmpty {
            error("BR-06", "An invoice must have the seller name (BT-27).")
        }
        if invoice.buyer.legalName.trimmed.isEmpty {
            error("BR-07", "An invoice must have the buyer name (BT-44).")
        }
        if invoice.seller.address.countryCode.trimmed.isEmpty {
            error("BR-09", "The seller address must contain a country code (BT-40).")
        }
        if invoice.buyer.address.countryCode.trimmed.isEmpty {
            error("BR-11", "The buyer address must contain a country code (BT-55).")
        }
        if invoice.lines.isEmpty {
            error("BR-16", "An invoice must have at least one invoice line (BG-25).")
        }
        if invoice.currency.code.count != 3 {
            error("BR-05", "The invoice must have a valid 3-letter currency code (BT-5).")
        }
        if invoice.dueDate < invoice.issueDate {
            warning("BR-CO-25", "The payment due date (BT-9) is before the issue date (BT-2).")
        }

        validateMonetarySummation(totals, into: &issues)
        validateVATBreakdowns(invoice, totals: totals, into: &issues)
        validateCreditNote(invoice, into: &issues)

        return issues
    }

    /// Whether the invoice may be issued as a compliant e-invoice (no errors).
    public static func isCompliant(_ invoice: Invoice) -> Bool {
        !validate(invoice).contains { $0.severity == .error }
    }

    private static func validateMonetarySummation(_ totals: ComputedTotals, into issues: inout [ValidationIssue]) {
        let s = totals.summary
        let recomputedLineTotal = Money.sum(totals.lineNets, currency: totals.currency)
        if recomputedLineTotal != s.lineTotal {
            issues.append(.init(severity: .error, rule: "BR-CO-10",
                message: "Sum of line nets (BT-131) must equal the line total (BT-106)."))
        }
        let expectedExclusive = s.lineTotal - s.allowanceTotal + s.chargeTotal
        if expectedExclusive != s.taxExclusiveTotal {
            issues.append(.init(severity: .error, rule: "BR-CO-13",
                message: "Tax-exclusive total (BT-109) must equal line total − allowances + charges."))
        }
        let expectedTaxTotal = Money.sum(totals.breakdowns.map(\.taxAmount), currency: totals.currency)
        if expectedTaxTotal != s.taxTotal {
            issues.append(.init(severity: .error, rule: "BR-CO-14",
                message: "Total VAT (BT-110) must equal the sum of VAT category amounts (BT-117)."))
        }
        if s.taxExclusiveTotal + s.taxTotal != s.taxInclusiveTotal {
            issues.append(.init(severity: .error, rule: "BR-CO-15",
                message: "Tax-inclusive total (BT-112) must equal tax-exclusive total + total VAT."))
        }
        if s.taxInclusiveTotal - s.prepaidAmount != s.payableAmount {
            issues.append(.init(severity: .error, rule: "BR-CO-16",
                message: "Amount due (BT-115) must equal tax-inclusive total − prepaid amount."))
        }
    }

    private static func validateVATBreakdowns(_ invoice: Invoice, totals: ComputedTotals, into issues: inout [ValidationIssue]) {
        let sellerHasVAT = invoice.seller.hasVATID
        let buyerHasVAT = invoice.buyer.hasVATID

        for breakdown in totals.breakdowns {
            let cat = breakdown.category
            let rate = breakdown.ratePercent

            if cat == .standard && rate <= 0 {
                issues.append(.init(severity: .error, rule: "BR-S-05",
                    message: "A standard-rated line (S) must have a VAT rate greater than zero (BT-152)."))
            }
            if cat.requiresZeroRate && rate != 0 {
                issues.append(.init(severity: .error, rule: "BR-\(cat.rawValue)-05",
                    message: "A \(cat.displayName) line must have a VAT rate of 0% (BT-152)."))
            }
            if cat == .standard {
                let expectedTax = Money(rounding: breakdown.taxableBase.amount * rate / 100, in: totals.currency)
                if expectedTax != breakdown.taxAmount {
                    issues.append(.init(severity: .error, rule: "BR-S-08",
                        message: "VAT amount (BT-117) must equal base × rate for the \(rate)% group."))
                }
            }
            if cat.requiresExemptionReason && breakdown.exemptionReason.trimmed.isEmpty {
                issues.append(.init(severity: .error, rule: "BR-\(cat.rawValue)-10",
                    message: "A \(cat.displayName) breakdown must carry an exemption reason (BT-120)."))
            }
            if cat.requiresBothVATIDs {
                if !sellerHasVAT {
                    issues.append(.init(severity: .error, rule: "BR-\(cat.rawValue)-02",
                        message: "\(cat.displayName) requires the seller VAT identifier (BT-31)."))
                }
                if !buyerHasVAT {
                    issues.append(.init(severity: .error, rule: "BR-\(cat.rawValue)-03",
                        message: "\(cat.displayName) requires the buyer VAT identifier (BT-48)."))
                }
            }
            if cat == .standard && !sellerHasVAT {
                issues.append(.init(severity: .error, rule: "BR-S-02",
                    message: "A standard-rated invoice requires the seller VAT identifier (BT-31)."))
            }
        }

        if sellerHasVAT {
            let prefix = invoice.seller.vatCountryPrefix
            if !prefix.allSatisfy({ $0.isLetter }) || prefix.count != 2 {
                issues.append(.init(severity: .warning, rule: "BR-CO-09",
                    message: "The seller VAT identifier (BT-31) should start with a 2-letter country code."))
            }
        }
    }

    private static func validateCreditNote(_ invoice: Invoice, into issues: inout [ValidationIssue]) {
        guard invoice.type == .creditNote else { return }
        if invoice.precedingInvoiceNumber.trimmed.isEmpty {
            issues.append(.init(severity: .warning, rule: "BR-55",
                message: "A credit note should reference the preceding invoice number (BT-25)."))
        }
    }
}

import Foundation

/// Emits OASIS UBL 2.1 `Invoice` / `CreditNote` conforming to Peppol BIS
/// Billing 3.0 — the payload transmitted over the Peppol network. UBL is also
/// `xsd:sequence`-ordered; the writer follows the BIS ordering.
public struct UBLInvoiceWriter: Sendable {
    public init() {}

    private enum NS {
        static let cac = "urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
        static let cbc = "urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2"
        static let invoice = "urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
        static let creditNote = "urn:oasis:names:specification:ubl:schema:xsd:CreditNote-2"
    }

    public func xml(for invoice: Invoice) throws -> String {
        guard invoice.type.isEInvoiceable else { throw EInvoiceError.notEInvoiceable(invoice.type) }
        let issues = InvoiceValidator.validate(invoice)
        if issues.contains(where: { $0.severity == .error }) {
            throw EInvoiceError.validationFailed(issues.filter { $0.severity == .error })
        }
        return buildXML(for: invoice).serialize()
    }

    public func buildXML(for invoice: Invoice) -> XMLBuilder {
        let isCredit = invoice.type == .creditNote
        let totals = invoice.totals()
        let cur = invoice.currency.code

        let root = XMLBuilder(isCredit ? "CreditNote" : "Invoice")
            .attr("xmlns", isCredit ? NS.creditNote : NS.invoice)
            .attr("xmlns:cac", NS.cac)
            .attr("xmlns:cbc", NS.cbc)

        root.element("cbc:CustomizationID", PeppolIdentifiers.customizationID)
        root.element("cbc:ProfileID", PeppolIdentifiers.profileID)
        root.element("cbc:ID", invoice.number)
        root.element("cbc:IssueDate", invoice.issueDate.iso8601)
        if !isCredit {
            root.element("cbc:DueDate", invoice.dueDate.iso8601)
        }
        root.element(isCredit ? "cbc:CreditNoteTypeCode" : "cbc:InvoiceTypeCode", invoice.type.typeCode)
        if !invoice.note.trimmed.isEmpty {
            root.element("cbc:Note", invoice.note)
        }
        root.element("cbc:DocumentCurrencyCode", cur)
        root.element("cbc:BuyerReference", invoice.buyerReference.trimmed.isEmpty ? nil : invoice.buyerReference)
        if !invoice.purchaseOrderReference.trimmed.isEmpty {
            let orderRef = XMLBuilder("cac:OrderReference")
            orderRef.element("cbc:ID", invoice.purchaseOrderReference)
            root.add(orderRef)
        }
        if isCredit && !invoice.precedingInvoiceNumber.trimmed.isEmpty {
            let billing = XMLBuilder("cac:BillingReference")
            let ref = XMLBuilder("cac:InvoiceDocumentReference")
            ref.element("cbc:ID", invoice.precedingInvoiceNumber)
            billing.add(ref)
            root.add(billing)
        }

        root.add(supplierParty(invoice.seller))
        root.add(customerParty(invoice.buyer))
        // PEPPOL-EN16931 intra-community supply rules: BR-IC-11 requires the actual
        // delivery date (BT-72, issue date is the accepted default) and BR-IC-12
        // requires the deliver-to country (BT-80) — the buyer's country for an IC supply.
        if invoice.lines.contains(where: { $0.vatCategory == .intraCommunity }) {
            let delivery = XMLBuilder("cac:Delivery")
            delivery.element("cbc:ActualDeliveryDate", invoice.issueDate.iso8601)
            let location = XMLBuilder("cac:DeliveryLocation")
            let address = XMLBuilder("cac:Address")
            let country = XMLBuilder("cac:Country")
            country.element("cbc:IdentificationCode", invoice.buyer.address.countryCode)
            address.add(country)
            location.add(address)
            delivery.add(location)
            root.add(delivery)
        }
        if !invoice.paymentMeans.iban.trimmed.isEmpty || isCredit {
            root.add(paymentMeans(invoice.paymentMeans, paymentDueDate: isCredit ? invoice.dueDate : nil))
        }
        if !invoice.paymentTerms.trimmed.isEmpty {
            let terms = XMLBuilder("cac:PaymentTerms")
            terms.element("cbc:Note", invoice.paymentTerms)
            root.add(terms)
        }
        for adjustment in invoice.adjustments {
            root.add(documentAllowanceCharge(adjustment, currency: invoice.currency, cur: cur))
        }
        root.add(taxTotal(totals, cur: cur))
        root.add(legalMonetaryTotal(totals, cur: cur))
        for (index, line) in invoice.lines.enumerated() {
            root.add(invoiceLine(line, net: totals.lineNets[index], position: index + 1, cur: cur, isCredit: isCredit))
        }
        return root
    }

    private func supplierParty(_ party: Party) -> XMLBuilder {
        let node = XMLBuilder("cac:AccountingSupplierParty")
        node.add(partyNode(party))
        return node
    }

    private func customerParty(_ party: Party) -> XMLBuilder {
        let node = XMLBuilder("cac:AccountingCustomerParty")
        node.add(partyNode(party))
        return node
    }

    private func partyNode(_ party: Party) -> XMLBuilder {
        let p = XMLBuilder("cac:Party")
        let peppol = party.peppolParticipant
        if !peppol.isEmpty {
            p.add(XMLBuilder("cbc:EndpointID", text: peppol.endpointID).attr("schemeID", peppol.schemeID))
        }
        let postal = XMLBuilder("cac:PostalAddress")
        postal.element("cbc:StreetName", emptyToNil(party.address.line1))
        postal.element("cbc:AdditionalStreetName", emptyToNil(party.address.line2))
        postal.element("cbc:CityName", emptyToNil(party.address.city))
        postal.element("cbc:PostalZone", emptyToNil(party.address.postalCode))
        if !party.address.countryCode.trimmed.isEmpty {
            let country = XMLBuilder("cac:Country")
            country.element("cbc:IdentificationCode", party.address.countryCode)
            postal.add(country)
        }
        p.add(postal)
        if party.hasVATID {
            let scheme = XMLBuilder("cac:PartyTaxScheme")
            scheme.element("cbc:CompanyID", party.vatID)
            let taxScheme = XMLBuilder("cac:TaxScheme")
            taxScheme.element("cbc:ID", "VAT")
            scheme.add(taxScheme)
            p.add(scheme)
        }
        let legal = XMLBuilder("cac:PartyLegalEntity")
        legal.element("cbc:RegistrationName", party.legalName)
        if !party.legalRegistrationID.trimmed.isEmpty {
            legal.element("cbc:CompanyID", party.legalRegistrationID)
        }
        p.add(legal)
        if !party.email.trimmed.isEmpty || !party.contactName.trimmed.isEmpty {
            let contact = XMLBuilder("cac:Contact")
            contact.element("cbc:Name", emptyToNil(party.contactName))
            contact.element("cbc:Telephone", emptyToNil(party.phone))
            contact.element("cbc:ElectronicMail", emptyToNil(party.email))
            p.add(contact)
        }
        return p
    }

    /// BG-20 / BG-21 — a document-level allowance or charge, rounded exactly as
    /// the `TaxEngine` folded it into the VAT base and totals (BR-CO-11/12).
    private func documentAllowanceCharge(_ adjustment: DocumentAdjustment, currency: Currency, cur: String) -> XMLBuilder {
        let rounded = Money(rounding: adjustment.amount, in: currency)
        let amount = Money(minorUnits: abs(rounded.minorUnits), currency: currency)
        let node = XMLBuilder("cac:AllowanceCharge")
        node.element("cbc:ChargeIndicator", adjustment.isCharge ? "true" : "false")
        node.element("cbc:AllowanceChargeReason", adjustment.reason.trimmed.isEmpty ? (adjustment.isCharge ? "Charge" : "Discount") : adjustment.reason)
        node.add(XMLBuilder("cbc:Amount", text: amount.canonicalString).attr("currencyID", cur))
        let category = XMLBuilder("cac:TaxCategory")
        category.element("cbc:ID", adjustment.vatCategory.rawValue)
        if adjustment.vatCategory.emitsRate {
            category.element("cbc:Percent", decimalString(adjustment.effectiveRate, scale: 2))
        }
        let taxScheme = XMLBuilder("cac:TaxScheme")
        taxScheme.element("cbc:ID", "VAT")
        category.add(taxScheme)
        node.add(category)
        return node
    }

    private func paymentMeans(_ means: PaymentMeans, paymentDueDate: CalendarDate?) -> XMLBuilder {
        let node = XMLBuilder("cac:PaymentMeans")
        node.element("cbc:PaymentMeansCode", means.method.rawValue)
        if let paymentDueDate {
            node.element("cbc:PaymentDueDate", paymentDueDate.iso8601)
        }
        if !means.remittanceReference.trimmed.isEmpty {
            node.element("cbc:PaymentID", means.remittanceReference)
        }
        if !means.iban.trimmed.isEmpty {
            let account = XMLBuilder("cac:PayeeFinancialAccount")
            account.element("cbc:ID", means.normalizedIBAN)
            if !means.accountName.trimmed.isEmpty {
                account.element("cbc:Name", means.accountName)
            }
            if !means.bic.trimmed.isEmpty {
                let branch = XMLBuilder("cac:FinancialInstitutionBranch")
                branch.element("cbc:ID", means.normalizedBIC)
                account.add(branch)
            }
            node.add(account)
        }
        return node
    }

    private func taxTotal(_ totals: ComputedTotals, cur: String) -> XMLBuilder {
        let node = XMLBuilder("cac:TaxTotal")
        node.add(XMLBuilder("cbc:TaxAmount", text: totals.summary.taxTotal.canonicalString).attr("currencyID", cur))
        for breakdown in totals.breakdowns {
            let sub = XMLBuilder("cac:TaxSubtotal")
            sub.add(XMLBuilder("cbc:TaxableAmount", text: breakdown.taxableBase.canonicalString).attr("currencyID", cur))
            sub.add(XMLBuilder("cbc:TaxAmount", text: breakdown.taxAmount.canonicalString).attr("currencyID", cur))
            let category = XMLBuilder("cac:TaxCategory")
            category.element("cbc:ID", breakdown.category.rawValue)
            if breakdown.category.emitsRate {
                category.element("cbc:Percent", decimalString(breakdown.ratePercent, scale: 2))
            }
            if breakdown.category.requiresExemptionReason && !breakdown.exemptionReason.isEmpty {
                category.element("cbc:TaxExemptionReason", breakdown.exemptionReason)
            }
            let taxScheme = XMLBuilder("cac:TaxScheme")
            taxScheme.element("cbc:ID", "VAT")
            category.add(taxScheme)
            sub.add(category)
            node.add(sub)
        }
        return node
    }

    private func legalMonetaryTotal(_ totals: ComputedTotals, cur: String) -> XMLBuilder {
        let s = totals.summary
        let node = XMLBuilder("cac:LegalMonetaryTotal")
        node.add(XMLBuilder("cbc:LineExtensionAmount", text: s.lineTotal.canonicalString).attr("currencyID", cur))
        node.add(XMLBuilder("cbc:TaxExclusiveAmount", text: s.taxExclusiveTotal.canonicalString).attr("currencyID", cur))
        node.add(XMLBuilder("cbc:TaxInclusiveAmount", text: s.taxInclusiveTotal.canonicalString).attr("currencyID", cur))
        if !s.allowanceTotal.isZero {
            node.add(XMLBuilder("cbc:AllowanceTotalAmount", text: s.allowanceTotal.canonicalString).attr("currencyID", cur))
        }
        if !s.chargeTotal.isZero {
            node.add(XMLBuilder("cbc:ChargeTotalAmount", text: s.chargeTotal.canonicalString).attr("currencyID", cur))
        }
        if !s.prepaidAmount.isZero {
            node.add(XMLBuilder("cbc:PrepaidAmount", text: s.prepaidAmount.canonicalString).attr("currencyID", cur))
        }
        node.add(XMLBuilder("cbc:PayableAmount", text: s.payableAmount.canonicalString).attr("currencyID", cur))
        return node
    }

    private func invoiceLine(_ line: LineItem, net: Money, position: Int, cur: String, isCredit: Bool) -> XMLBuilder {
        let node = XMLBuilder(isCredit ? "cac:CreditNoteLine" : "cac:InvoiceLine")
        node.element("cbc:ID", String(position))
        let qtyTag = isCredit ? "cbc:CreditedQuantity" : "cbc:InvoicedQuantity"
        node.add(XMLBuilder(qtyTag, text: decimalString(line.quantity, scale: 4)).attr("unitCode", line.unit.rawValue))
        node.add(XMLBuilder("cbc:LineExtensionAmount", text: net.canonicalString).attr("currencyID", cur))

        // PEPPOL-EN16931-R120: line net (BT-131) must equal quantity × price minus
        // line allowances. A per-line discount is declared as a line AllowanceCharge
        // (BG-27) whose amount is exactly round(qty × price) − net, so the rule holds
        // by construction regardless of how the engine rounded the discounted net.
        let grossRounded = Money(rounding: line.quantity * line.unitPrice, in: net.currency)
        let allowanceMinor = grossRounded.minorUnits - net.minorUnits
        if allowanceMinor != 0 {
            let isCharge = allowanceMinor < 0
            let allowance = Money(minorUnits: abs(allowanceMinor), currency: net.currency)
            let ac = XMLBuilder("cac:AllowanceCharge")
            ac.element("cbc:ChargeIndicator", isCharge ? "true" : "false")
            ac.element("cbc:AllowanceChargeReason", "Discount")
            ac.add(XMLBuilder("cbc:Amount", text: allowance.canonicalString).attr("currencyID", cur))
            node.add(ac)
        }

        let item = XMLBuilder("cac:Item")
        if !line.details.trimmed.isEmpty {
            item.element("cbc:Description", line.details)
        }
        item.element("cbc:Name", line.name.isEmpty ? "Item" : line.name)
        let taxCategory = XMLBuilder("cac:ClassifiedTaxCategory")
        taxCategory.element("cbc:ID", line.vatCategory.rawValue)
        if line.vatCategory.emitsRate {
            taxCategory.element("cbc:Percent", decimalString(line.effectiveRate, scale: 2))
        }
        let taxScheme = XMLBuilder("cac:TaxScheme")
        taxScheme.element("cbc:ID", "VAT")
        taxCategory.add(taxScheme)
        item.add(taxCategory)
        node.add(item)

        let price = XMLBuilder("cac:Price")
        price.add(XMLBuilder("cbc:PriceAmount", text: decimalString(line.unitPrice, scale: 4)).attr("currencyID", cur))
        node.add(price)
        return node
    }

    private func emptyToNil(_ s: String) -> String? {
        let t = s.trimmed
        return t.isEmpty ? nil : t
    }

    private func decimalString(_ value: Decimal, scale: Int) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, scale, .plain)
        let formatted = (rounded as NSDecimalNumber).stringValue
        return formatted.contains(".") ? formatted : formatted + ".00"
    }
}

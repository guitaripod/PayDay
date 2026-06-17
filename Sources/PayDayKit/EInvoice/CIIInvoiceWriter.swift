import Foundation

/// Emits a UN/CEFACT Cross-Industry Invoice (CII, D16B) conforming to EN 16931
/// — the `factur-x.xml` payload embedded in a Factur-X / ZUGFeRD hybrid PDF.
///
/// The element order follows the CII XSD `xsd:sequence`, which is mandatory:
/// `ExchangedDocumentContext` → `ExchangedDocument` → `SupplyChainTradeTransaction`
/// (lines → `ApplicableHeaderTradeAgreement` → `…Delivery` → `…Settlement`).
public struct CIIInvoiceWriter: Sendable {
    public let profile: EInvoiceProfile

    public init(profile: EInvoiceProfile = .en16931) {
        self.profile = profile
    }

    private enum NS {
        static let rsm = "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"
        static let ram = "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"
        static let udt = "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"
        static let qdt = "urn:un:unece:uncefact:data:standard:QualifiedDataType:100"
    }

    /// Produce the CII XML string. Throws if the document is not e-invoiceable
    /// or fails EN 16931 validation (so we never emit a non-compliant payload).
    public func xml(for invoice: Invoice) throws -> String {
        guard invoice.type.isEInvoiceable else { throw EInvoiceError.notEInvoiceable(invoice.type) }
        let issues = InvoiceValidator.validate(invoice)
        if issues.contains(where: { $0.severity == .error }) {
            throw EInvoiceError.validationFailed(issues.filter { $0.severity == .error })
        }
        return buildXML(for: invoice).serialize()
    }

    /// Build the XML tree without validating — useful for previews and tests.
    public func buildXML(for invoice: Invoice) -> XMLBuilder {
        let totals = invoice.totals()
        let cur = invoice.currency.code

        let root = XMLBuilder("rsm:CrossIndustryInvoice")
            .attr("xmlns:rsm", NS.rsm)
            .attr("xmlns:ram", NS.ram)
            .attr("xmlns:udt", NS.udt)
            .attr("xmlns:qdt", NS.qdt)

        root.add(context())
        root.add(exchangedDocument(invoice))
        root.add(tradeTransaction(invoice, totals: totals, cur: cur))
        return root
    }

    private func context() -> XMLBuilder {
        let ctx = XMLBuilder("rsm:ExchangedDocumentContext")
        let process = XMLBuilder("ram:BusinessProcessSpecifiedDocumentContextParameter")
        process.element("ram:ID", PeppolIdentifiers.profileID)
        ctx.add(process)
        let guideline = XMLBuilder("ram:GuidelineSpecifiedDocumentContextParameter")
        guideline.element("ram:ID", profile.ciiGuidelineID)
        ctx.add(guideline)
        return ctx
    }

    private func exchangedDocument(_ invoice: Invoice) -> XMLBuilder {
        let doc = XMLBuilder("rsm:ExchangedDocument")
        doc.element("ram:ID", invoice.number)
        doc.element("ram:TypeCode", invoice.type.typeCode)
        let issue = XMLBuilder("ram:IssueDateTime")
        let dateString = XMLBuilder("udt:DateTimeString", text: invoice.issueDate.ciiString).attr("format", "102")
        issue.add(dateString)
        doc.add(issue)
        if !invoice.note.trimmed.isEmpty {
            let note = XMLBuilder("ram:IncludedNote")
            note.element("ram:Content", invoice.note)
            doc.add(note)
        }
        return doc
    }

    private func tradeTransaction(_ invoice: Invoice, totals: ComputedTotals, cur: String) -> XMLBuilder {
        let tx = XMLBuilder("rsm:SupplyChainTradeTransaction")
        for (index, line) in invoice.lines.enumerated() {
            tx.add(lineItem(line, net: totals.lineNets[index], position: index + 1, cur: cur))
        }
        tx.add(headerAgreement(invoice))
        tx.add(headerDelivery(invoice))
        tx.add(headerSettlement(invoice, totals: totals, cur: cur))
        return tx
    }

    private func lineItem(_ line: LineItem, net: Money, position: Int, cur: String) -> XMLBuilder {
        let item = XMLBuilder("ram:IncludedSupplyChainTradeLineItem")

        let docLine = XMLBuilder("ram:AssociatedDocumentLineDocument")
        docLine.element("ram:LineID", String(position))
        item.add(docLine)

        let product = XMLBuilder("ram:SpecifiedTradeProduct")
        product.element("ram:Name", line.name.isEmpty ? "Item" : line.name)
        if !line.details.trimmed.isEmpty {
            product.element("ram:Description", line.details)
        }
        item.add(product)

        let agreement = XMLBuilder("ram:SpecifiedLineTradeAgreement")
        let netPrice = XMLBuilder("ram:NetPriceProductTradePrice")
        netPrice.element("ram:ChargeAmount", decimalString(line.unitPrice, scale: 4))
        agreement.add(netPrice)
        item.add(agreement)

        let delivery = XMLBuilder("ram:SpecifiedLineTradeDelivery")
        let qty = XMLBuilder("ram:BilledQuantity", text: decimalString(line.quantity, scale: 4))
            .attr("unitCode", line.unit.rawValue)
        delivery.add(qty)
        item.add(delivery)

        let settlement = XMLBuilder("ram:SpecifiedLineTradeSettlement")
        let tax = XMLBuilder("ram:ApplicableTradeTax")
        tax.element("ram:TypeCode", "VAT")
        tax.element("ram:CategoryCode", line.vatCategory.rawValue)
        tax.element("ram:RateApplicablePercent", decimalString(line.effectiveRate, scale: 2))
        settlement.add(tax)

        // A per-line discount is reconciled as a line allowance (BG-27), exactly
        // as the UBL writer does: the net price (BT-146) stays the full unit
        // price and the allowance amount is round(qty × price) − line net, so the
        // CII line-calculation rule (BT-131 = BT-146 × BT-129 − allowances) holds
        // by construction. Without this the embedded Factur-X XML fails EN 16931
        // validation on any discounted line.
        if let allowance = lineAllowance(line, net: net) {
            settlement.add(allowance)
        }

        let lineMon = XMLBuilder("ram:SpecifiedTradeSettlementLineMonetarySummation")
        lineMon.element("ram:LineTotalAmount", net.canonicalString)
        settlement.add(lineMon)
        item.add(settlement)

        return item
    }

    /// The BG-27 line allowance that represents a per-line discount, or `nil`
    /// when the line is undiscounted. The amount is `round(qty × price) − net`,
    /// computed from the engine's rounded values so the line calculation is exact.
    private func lineAllowance(_ line: LineItem, net: Money) -> XMLBuilder? {
        let grossRounded = Money(rounding: line.quantity * line.unitPrice, in: net.currency)
        let allowanceMinor = grossRounded.minorUnits - net.minorUnits
        guard allowanceMinor > 0 else { return nil }
        let amount = Money(minorUnits: allowanceMinor, currency: net.currency)
        let ac = XMLBuilder("ram:SpecifiedTradeAllowanceCharge")
        let indicator = XMLBuilder("ram:ChargeIndicator")
        indicator.element("udt:Indicator", "false")
        ac.add(indicator)
        ac.element("ram:ActualAmount", amount.canonicalString)
        ac.element("ram:Reason", "Discount")
        return ac
    }

    private func headerAgreement(_ invoice: Invoice) -> XMLBuilder {
        let agreement = XMLBuilder("ram:ApplicableHeaderTradeAgreement")
        agreement.element("ram:BuyerReference", emptyToNil(invoice.buyerReference))
        agreement.add(tradeParty("ram:SellerTradeParty", invoice.seller, includeContact: true))
        agreement.add(tradeParty("ram:BuyerTradeParty", invoice.buyer, includeContact: false))
        if !invoice.purchaseOrderReference.trimmed.isEmpty {
            let buyerRef = XMLBuilder("ram:BuyerOrderReferencedDocument")
            buyerRef.element("ram:IssuerAssignedID", invoice.purchaseOrderReference)
            agreement.add(buyerRef)
        }
        return agreement
    }

    private func headerDelivery(_ invoice: Invoice) -> XMLBuilder {
        XMLBuilder("ram:ApplicableHeaderTradeDelivery")
    }

    private func headerSettlement(_ invoice: Invoice, totals: ComputedTotals, cur: String) -> XMLBuilder {
        let settlement = XMLBuilder("ram:ApplicableHeaderTradeSettlement")
        if !invoice.paymentMeans.remittanceReference.trimmed.isEmpty {
            settlement.element("ram:PaymentReference", invoice.paymentMeans.remittanceReference)
        }
        settlement.element("ram:InvoiceCurrencyCode", cur)

        if !invoice.paymentMeans.iban.trimmed.isEmpty {
            let means = XMLBuilder("ram:SpecifiedTradeSettlementPaymentMeans")
            means.element("ram:TypeCode", invoice.paymentMeans.method.rawValue)
            let account = XMLBuilder("ram:PayeePartyCreditorFinancialAccount")
            account.element("ram:IBANID", invoice.paymentMeans.normalizedIBAN)
            if !invoice.paymentMeans.accountName.trimmed.isEmpty {
                account.element("ram:AccountName", invoice.paymentMeans.accountName)
            }
            means.add(account)
            settlement.add(means)
        }

        for breakdown in totals.breakdowns {
            let tax = XMLBuilder("ram:ApplicableTradeTax")
            tax.element("ram:CalculatedAmount", breakdown.taxAmount.canonicalString)
            tax.element("ram:TypeCode", "VAT")
            if breakdown.category.requiresExemptionReason && !breakdown.exemptionReason.isEmpty {
                tax.element("ram:ExemptionReason", breakdown.exemptionReason)
            }
            tax.element("ram:BasisAmount", breakdown.taxableBase.canonicalString)
            tax.element("ram:CategoryCode", breakdown.category.rawValue)
            tax.element("ram:RateApplicablePercent", decimalString(breakdown.ratePercent, scale: 2))
            settlement.add(tax)
        }

        let terms = XMLBuilder("ram:SpecifiedTradePaymentTerms")
        if !invoice.paymentTerms.trimmed.isEmpty {
            terms.element("ram:Description", invoice.paymentTerms)
        }
        let due = XMLBuilder("ram:DueDateDateTime")
        due.add(XMLBuilder("udt:DateTimeString", text: invoice.dueDate.ciiString).attr("format", "102"))
        terms.add(due)
        settlement.add(terms)

        settlement.add(monetarySummation(totals, cur: cur))

        if invoice.type == .creditNote && !invoice.precedingInvoiceNumber.trimmed.isEmpty {
            let ref = XMLBuilder("ram:InvoiceReferencedDocument")
            ref.element("ram:IssuerAssignedID", invoice.precedingInvoiceNumber)
            settlement.add(ref)
        }
        return settlement
    }

    private func monetarySummation(_ totals: ComputedTotals, cur: String) -> XMLBuilder {
        let s = totals.summary
        let mon = XMLBuilder("ram:SpecifiedTradeSettlementHeaderMonetarySummation")
        mon.element("ram:LineTotalAmount", s.lineTotal.canonicalString)
        if !s.chargeTotal.isZero {
            mon.element("ram:ChargeTotalAmount", s.chargeTotal.canonicalString)
        }
        if !s.allowanceTotal.isZero {
            mon.element("ram:AllowanceTotalAmount", s.allowanceTotal.canonicalString)
        }
        mon.element("ram:TaxBasisTotalAmount", s.taxExclusiveTotal.canonicalString)
        mon.add(XMLBuilder("ram:TaxTotalAmount", text: s.taxTotal.canonicalString).attr("currencyID", cur))
        mon.element("ram:GrandTotalAmount", s.taxInclusiveTotal.canonicalString)
        if !s.prepaidAmount.isZero {
            mon.element("ram:TotalPrepaidAmount", s.prepaidAmount.canonicalString)
        }
        mon.element("ram:DuePayableAmount", s.payableAmount.canonicalString)
        return mon
    }

    private func tradeParty(_ tag: String, _ party: Party, includeContact: Bool) -> XMLBuilder {
        let node = XMLBuilder(tag)
        node.element("ram:Name", party.legalName)
        if !party.legalRegistrationID.trimmed.isEmpty {
            let legal = XMLBuilder("ram:SpecifiedLegalOrganization")
            legal.element("ram:ID", party.legalRegistrationID)
            node.add(legal)
        }
        if includeContact, let contact = definedTradeContact(party) {
            node.add(contact)
        }
        let address = XMLBuilder("ram:PostalTradeAddress")
        address.element("ram:PostcodeCode", emptyToNil(party.address.postalCode))
        address.element("ram:LineOne", emptyToNil(party.address.line1))
        address.element("ram:LineTwo", emptyToNil(party.address.line2))
        address.element("ram:CityName", emptyToNil(party.address.city))
        address.element("ram:CountryID", emptyToNil(party.address.countryCode))
        node.add(address)
        if !party.email.trimmed.isEmpty {
            let comm = XMLBuilder("ram:URIUniversalCommunication")
            comm.add(XMLBuilder("ram:URIID", text: party.email).attr("schemeID", "EM"))
            node.add(comm)
        }
        if party.hasVATID {
            let reg = XMLBuilder("ram:SpecifiedTaxRegistration")
            reg.add(XMLBuilder("ram:ID", text: party.vatID).attr("schemeID", "VA"))
            node.add(reg)
        }
        return node
    }

    /// BG-6 SELLER CONTACT, emitted when the party carries any contact detail.
    private func definedTradeContact(_ party: Party) -> XMLBuilder? {
        let name = party.contactName.trimmed
        let phone = party.phone.trimmed
        let email = party.email.trimmed
        guard !name.isEmpty || !phone.isEmpty || !email.isEmpty else { return nil }
        let contact = XMLBuilder("ram:DefinedTradeContact")
        contact.element("ram:PersonName", emptyToNil(name))
        if !phone.isEmpty {
            let tel = XMLBuilder("ram:TelephoneUniversalCommunication")
            tel.element("ram:CompleteNumber", phone)
            contact.add(tel)
        }
        if !email.isEmpty {
            let mail = XMLBuilder("ram:EmailURIUniversalCommunication")
            mail.element("ram:URIID", email)
            contact.add(mail)
        }
        return contact
    }

    private func emptyToNil(_ s: String) -> String? {
        let t = s.trimmed
        return t.isEmpty ? nil : t
    }

    /// Render a decimal with a fixed maximum scale, trimming to at least one
    /// fraction digit — the form CII expects for rates, prices, and quantities.
    private func decimalString(_ value: Decimal, scale: Int) -> String {
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, scale, .plain)
        let number = rounded as NSDecimalNumber
        let formatted = number.stringValue
        if !formatted.contains(".") {
            return formatted + ".00"
        }
        return formatted
    }
}

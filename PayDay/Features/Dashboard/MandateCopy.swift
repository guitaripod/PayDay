import Foundation
import PayDayKit

/// Everything the dashboard card and the welcome screen say about a country's
/// e-invoicing regime, resolved from the Kit's dated facts into localized copy.
struct MandateCardModel: Equatable {
    enum Tone: Equatable { case urgent, active, upcoming, neutral }
    enum Action: Equatable { case unlockPro(reason: String), openPeppolSettings, openBusinessSettings, informationOnly }

    let title: String
    let pillTitle: String
    let tone: Tone
    let body: String
    let deadline: String?
    let actionTitle: String?
    let action: Action
}

enum MandateCopy {
    /// The card for a seller in `countryCode`, or nil when there is nothing to say
    /// (outside the EU, or an unknown code).
    static func card(countryCode: String, isPro: Bool, peppolConfigured: Bool,
                     today: CalendarDate = Format.today(), locale: Locale = .current) -> MandateCardModel? {
        guard let mandate = EInvoicingMandates.mandate(for: countryCode) else { return nil }
        let country = countryName(mandate.countryCode, locale: locale)
        let phase = mandate.phase(on: today)
        let (pill, tone) = pill(for: phase, locale: locale)
        let deadline: String? = {
            switch phase {
            case .phasingIn(let next), .scheduled(let next):
                return String(localized: "Next: \(Format.date(next.date, style: .long, locale: locale)) — \(scopePhrase(next.scope))",
                              comment: "Dashboard card deadline line: a date, then who becomes obliged on it")
            case .inForce, .noMandate:
                return nil
            }
        }()
        let (actionTitle, action) = action(for: mandate, country: country, isPro: isPro, peppolConfigured: peppolConfigured)
        return MandateCardModel(
            title: String(localized: "E-invoicing in \(country)", comment: "Dashboard card title; the argument is a country name"),
            pillTitle: pill, tone: tone,
            body: summary(for: mandate, country: country),
            deadline: deadline, actionTitle: actionTitle, action: action)
    }

    /// One line for the welcome screen, keyed off the device region. Nil when the
    /// regime has no dated obligation Pay Day can help with.
    static func welcomeLine(countryCode: String, today: CalendarDate = Format.today(), locale: Locale = .current) -> String? {
        guard let mandate = EInvoicingMandates.mandate(for: countryCode) else { return nil }
        if case .nationalPlatform = mandate.channel { return nil }
        let country = countryName(mandate.countryCode, locale: locale)
        switch mandate.phase(on: today) {
        case .inForce(let since):
            return String(localized: "\(country): e-invoicing is mandatory for every business since \(Format.date(since, style: .long, locale: locale)).",
                          comment: "Welcome screen hook; arguments are a country name and a date")
        case .phasingIn(let next):
            return String(localized: "\(country): e-invoicing is phasing in — next deadline \(Format.date(next.date, style: .long, locale: locale)).",
                          comment: "Welcome screen hook; arguments are a country name and a date")
        case .scheduled(let first):
            return String(localized: "\(country): mandatory e-invoicing starts \(Format.date(first.date, style: .long, locale: locale)).",
                          comment: "Welcome screen hook; arguments are a country name and a date")
        case .noMandate:
            return nil
        }
    }

    static func countryName(_ code: String, locale: Locale) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    private static func pill(for phase: EInvoicingMandate.Phase, locale: Locale) -> (String, MandateCardModel.Tone) {
        switch phase {
        case .inForce:
            return (String(localized: "Mandatory now", comment: "Status pill"), .urgent)
        case .phasingIn:
            return (String(localized: "Phasing in", comment: "Status pill"), .active)
        case .scheduled(let first):
            return (String(localized: "From \(Format.date(first.date, style: .medium, locale: locale))", comment: "Status pill; the argument is a date"), .upcoming)
        case .noMandate:
            return (String(localized: "No B2B mandate yet", comment: "Status pill"), .neutral)
        }
    }

    private static func scopePhrase(_ scope: EInvoicingMandate.Scope) -> String {
        switch scope {
        case .receiveAll: return String(localized: "every business must accept e-invoices", comment: "Deadline scope phrase")
        case .issueLarge: return String(localized: "large companies must issue e-invoices", comment: "Deadline scope phrase")
        case .issueSmall: return String(localized: "small businesses must issue e-invoices", comment: "Deadline scope phrase")
        case .issueAll: return String(localized: "every business must issue e-invoices", comment: "Deadline scope phrase")
        }
    }

    private static func action(for mandate: EInvoicingMandate, country: String, isPro: Bool, peppolConfigured: Bool) -> (String?, MandateCardModel.Action) {
        switch mandate.channel {
        case .nationalPlatform:
            return (nil, .informationOnly)
        case .peppol:
            if !isPro {
                return (String(localized: "Unlock Peppol delivery"),
                        .unlockPro(reason: String(localized: "Send compliant e-invoices over Peppol from \(country).",
                                                  comment: "Paywall reason; the argument is a country name")))
            }
            if !peppolConfigured {
                return (String(localized: "Add your Peppol ID"), .openPeppolSettings)
            }
            return (String(localized: "You're Peppol-ready"), .openBusinessSettings)
        case .unspecified:
            if !isPro {
                return (String(localized: "Unlock Factur-X e-invoices"),
                        .unlockPro(reason: String(localized: "Issue EN 16931 e-invoices that \(country)'s mandate accepts.",
                                                  comment: "Paywall reason; the argument is a country name")))
            }
            return (String(localized: "You're e-invoice-ready"), .openBusinessSettings)
        }
    }

    private static func summary(for mandate: EInvoicingMandate, country: String) -> String {
        switch mandate.countryCode {
        case "BE":
            return String(localized: "Every VAT-registered business in Belgium must send and receive structured e-invoices over Peppol since 1 January 2026. A PDF or paper invoice no longer counts, and fines start at €1,500.")
        case "FR":
            return String(localized: "Every business in France must be able to receive e-invoices since 1 September 2026. Large and mid-sized companies already issue them; small businesses and micro-entrepreneurs must from 1 September 2027, through an accredited platform (PDP). Factur-X is an accepted format.")
        case "DE":
            return String(localized: "Every business in Germany must be able to receive e-invoices since 1 January 2025. Companies above €800,000 turnover must issue them from 1 January 2027, everyone else from 1 January 2028. ZUGFeRD / Factur-X and XRechnung are the accepted formats.")
        case "NL":
            return String(localized: "The Netherlands has no B2B mandate yet, but Peppol is the national standard and mandatory for government suppliers. EU-wide cross-border e-invoicing becomes mandatory on 1 July 2030.")
        case "FI":
            return String(localized: "In Finland any business can require a structured e-invoice from you (Act 241/2019), and government suppliers must send them. Peppol with an OVT address is the standard.")
        case "SE":
            return String(localized: "Sweden has no B2B mandate yet, but Peppol is the national standard and mandatory for government suppliers. EU-wide cross-border e-invoicing becomes mandatory on 1 July 2030.")
        case "DK":
            return String(localized: "Under Denmark's Bookkeeping Act, digital bookkeeping systems send e-invoices via NemHandel / Peppol by default since July 2026, and government suppliers must use them. EU-wide cross-border e-invoicing becomes mandatory on 1 July 2030.")
        case "NO":
            return String(localized: "Norway requires every business to issue e-invoices in the Peppol-based EHF format from 1 January 2027 — a PDF by email will no longer count. Receiving follows on 1 January 2030.")
        case "AT":
            return String(localized: "Austria has no B2B mandate yet, but federal suppliers must send e-invoices and Peppol is the standard. EU-wide cross-border e-invoicing becomes mandatory on 1 July 2030.")
        case "LU":
            return String(localized: "Luxembourg requires every supplier to public bodies to send e-invoices over Peppol. A bill before Parliament would phase in B2B e-invoicing over Peppol from 2028 to 2029.")
        case "IE":
            return String(localized: "Ireland phases in mandatory B2B e-invoicing over Peppol from 1 November 2028, starting with large companies, and extends it to all other VAT-registered businesses in November 2029.")
        case "EE":
            return String(localized: "In Estonia any registered e-invoice receiver can require a structured e-invoice from you since 1 July 2025, and a full B2B mandate is planned for 2027. Peppol is the common channel.")
        case "LV":
            return String(localized: "Latvia requires every business to issue and receive structured e-invoices from 1 January 2028, with invoice data reported to the State Revenue Service. Peppol is a supported channel.")
        case "SI":
            return String(localized: "Slovenia requires every business to exchange structured e-invoices from 1 January 2028, over Peppol or an accredited provider.")
        case "PT":
            return String(localized: "Portugal has no B2B mandate yet. From 1 January 2027 a PDF invoice needs a qualified electronic signature, while a structured e-invoice does not. EU-wide cross-border e-invoicing becomes mandatory on 1 July 2030.")
        case "PL":
            return String(localized: "Poland's KSeF platform is mandatory for B2B invoices since 2026. Pay Day produces EN 16931 e-invoices and Peppol sends, but does not submit to KSeF.")
        case "IT":
            return String(localized: "Italy's SDI platform has been mandatory for B2B invoices since 2019. Pay Day produces EN 16931 e-invoices and Peppol sends, but does not submit to SDI.")
        case "ES":
            return String(localized: "Spain phases in mandatory B2B e-invoicing from 1 October 2027 (turnover above €8 million) and 1 October 2028 (everyone else), through the public solution or a private platform. Pay Day produces EN 16931 e-invoices but does not yet connect to the Spanish platform.")
        case "GR":
            return String(localized: "Greece phases in mandatory B2B e-invoicing through myDATA: businesses above €1 million turnover since 2 March 2026, everyone else from 1 October 2026. Pay Day produces EN 16931 e-invoices but does not submit to myDATA.")
        case "RO":
            return String(localized: "Romania requires every business to send B2B invoices through RO e-Factura since July 2024. Pay Day produces EN 16931 e-invoices but does not submit to RO e-Factura.")
        case "HR":
            return String(localized: "Croatia requires VAT-registered businesses to issue and receive e-invoices over Peppol with real-time fiscal reporting since 1 January 2026; sole traders and non-VAT businesses follow on 1 January 2027. Pay Day delivers over Peppol but does not do the fiscal reporting.")
        case "SK":
            return String(localized: "Slovakia requires every VAT-registered business to issue, receive and report structured e-invoices from 1 January 2027, over a Peppol-based network with central reporting (IS EFA).")
        default:
            return String(localized: "\(country) has no national B2B e-invoicing mandate yet. EU-wide cross-border e-invoicing becomes mandatory on 1 July 2030.",
                          comment: "Generic EU fallback; the argument is a country name")
        }
    }
}

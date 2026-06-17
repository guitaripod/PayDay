import Foundation

/// How the buyer is asked to pay (BG-16). For a freelancer this is almost
/// always a SEPA credit transfer to an IBAN; the code follows UNCL 4461.
public struct PaymentMeans: Sendable, Equatable, Hashable, Codable {
    public enum Method: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
        /// SEPA / credit transfer.
        case creditTransfer = "58"
        /// Card.
        case card = "48"
        /// Direct debit.
        case directDebit = "59"
        /// Cash.
        case cash = "10"
        /// Other / undefined.
        case other = "1"

        public var displayName: String {
            switch self {
            case .creditTransfer: return "Bank transfer (SEPA)"
            case .card: return "Card"
            case .directDebit: return "Direct debit"
            case .cash: return "Cash"
            case .other: return "Other"
            }
        }
    }

    public var method: Method
    public var iban: String
    public var bic: String
    public var accountName: String
    /// A structured creditor reference / payment remittance note (BT-83).
    public var remittanceReference: String

    /// The IBAN stripped of the spaces banks print for readability and
    /// uppercased — the only form an EN 16931 Schematron / Peppol access point
    /// accepts on the wire (BT-84). Display keeps the user's spacing.
    public var normalizedIBAN: String {
        iban.filter { !$0.isWhitespace }.uppercased()
    }

    /// The BIC normalized the same way (BT-86).
    public var normalizedBIC: String {
        bic.filter { !$0.isWhitespace }.uppercased()
    }

    public init(
        method: Method = .creditTransfer,
        iban: String = "",
        bic: String = "",
        accountName: String = "",
        remittanceReference: String = ""
    ) {
        self.method = method
        self.iban = iban
        self.bic = bic
        self.accountName = accountName
        self.remittanceReference = remittanceReference
    }
}

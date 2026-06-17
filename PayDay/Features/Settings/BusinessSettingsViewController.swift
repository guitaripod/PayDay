import UIKit
import PayDayKit

/// Edits the seller business profile and invoice defaults. Saved values pre-fill
/// every new document, so this is the one form that pays off on every invoice.
final class BusinessSettingsViewController: UIViewController {
    private var profile = BusinessProfile()

    private let nameField = BusinessSettingsViewController.field("Legal name")
    private let vatField = BusinessSettingsViewController.field("VAT ID")
    private let regField = BusinessSettingsViewController.field("Company registration no.")
    private let line1Field = BusinessSettingsViewController.field("Street address")
    private let cityField = BusinessSettingsViewController.field("City")
    private let postalField = BusinessSettingsViewController.field("Postal code")
    private let countryField = BusinessSettingsViewController.field("Country code")
    private let ibanField = BusinessSettingsViewController.field("IBAN")
    private let bicField = BusinessSettingsViewController.field("BIC")
    private let peppolField = BusinessSettingsViewController.field("Your Peppol ID (scheme:id)")
    private let vatRateField = BusinessSettingsViewController.field("Default VAT %", keyboard: .decimalPad)
    private let termsField = BusinessSettingsViewController.field("Default payment terms")
    private let peppolStatusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Business"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = DesignSystem.Color.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .save, primaryAction: UIAction { [weak self] _ in self?.commit() })
        build()
        load()
    }

    private func load() {
        Task {
            let loaded = (try? await BusinessRepository.shared.load()) ?? BusinessProfile()
            await MainActor.run { self.profile = loaded; self.populate() }
        }
    }

    private func populate() {
        nameField.text = profile.seller.legalName
        vatField.text = profile.seller.vatID
        regField.text = profile.seller.legalRegistrationID
        line1Field.text = profile.seller.address.line1
        cityField.text = profile.seller.address.city
        postalField.text = profile.seller.address.postalCode
        countryField.text = profile.seller.address.countryCode
        ibanField.text = profile.paymentMeans.iban
        bicField.text = profile.paymentMeans.bic
        peppolField.text = profile.seller.peppolEndpointID.isEmpty ? "" : "\(profile.seller.peppolSchemeID):\(profile.seller.peppolEndpointID)"
        vatRateField.text = String(profile.defaultVATRatePercent)
        termsField.text = profile.defaultPaymentTerms
    }

    private func build() {
        peppolStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        peppolStatusLabel.textColor = DesignSystem.Color.secondary
        peppolStatusLabel.numberOfLines = 0

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [
            section("Identity"), nameField, vatField, regField,
            section("Address"), line1Field, cityField, postalField, countryField,
            section("Getting paid"), ibanField, bicField, peppolField, peppolStatusLabel,
            section("Defaults"), vatRateField, termsField,
        ])
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.s
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        scroll.pinEdges(toSafeAreaOf: view)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: DesignSystem.Spacing.m),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: DesignSystem.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -DesignSystem.Spacing.m),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -DesignSystem.Spacing.l),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -DesignSystem.Spacing.m * 2),
        ])
    }

    private func commit() {
        profile.seller.legalName = nameField.text ?? ""
        profile.seller.vatID = (vatField.text ?? "").normalizedVATID
        profile.seller.legalRegistrationID = regField.text ?? ""
        profile.seller.address = PostalAddress(
            line1: line1Field.text ?? "", city: cityField.text ?? "",
            postalCode: postalField.text ?? "", countryCode: countryField.text ?? "")
        profile.paymentMeans = PaymentMeans(
            method: .creditTransfer,
            iban: PaymentMeans(iban: ibanField.text ?? "").normalizedIBAN,
            bic: bicField.text ?? "", accountName: profile.seller.legalName)
        applyPeppol(peppolField.text ?? "")
        profile.defaultVATRatePercent = Double(vatRateField.text ?? "") ?? profile.defaultVATRatePercent
        profile.defaultPaymentTerms = termsField.text ?? ""
        AppSettings.defaultVATRatePercent = profile.defaultVATRatePercent
        Task {
            try? await BusinessRepository.shared.save(profile)
            await MainActor.run { self.navigationController?.popViewController(animated: true) }
        }
    }

    /// Always rewrites the seller's Peppol address from the field, so clearing
    /// it removes a stale endpoint instead of leaving one that would still be
    /// used for real delivery. Colon-less, non-empty input is surfaced as an
    /// advisory hint and the address is cleared (never blocks saving).
    private func applyPeppol(_ raw: String) {
        let input = raw.trimmed
        if input.isEmpty {
            profile.seller.peppolSchemeID = ""
            profile.seller.peppolEndpointID = ""
            peppolStatusLabel.text = nil
        } else if let colon = input.firstIndex(of: ":") {
            profile.seller.peppolSchemeID = String(input[..<colon]).trimmed
            profile.seller.peppolEndpointID = String(input[input.index(after: colon)...]).trimmed
            peppolStatusLabel.text = nil
        } else {
            profile.seller.peppolSchemeID = ""
            profile.seller.peppolEndpointID = ""
            peppolStatusLabel.text = "Use scheme:id, e.g. 0208:0123456789"
        }
    }

    private func section(_ title: String) -> UILabel {
        let label = DesignSystem.label(title.uppercased(), font: .systemFont(ofSize: 12, weight: .bold), color: DesignSystem.Color.secondary)
        return label
    }

    private static func field(_ placeholder: String, keyboard: UIKeyboardType = .default) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.keyboardType = keyboard
        field.font = DesignSystem.Typography.body()
        return field
    }
}

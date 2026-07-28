import UIKit
import PayDayKit

/// Edits the seller business profile and invoice defaults. Saved values pre-fill
/// every new document, so this is the one form that pays off on every invoice.
final class BusinessSettingsViewController: UIViewController {
    private var profile = BusinessProfile()

    private let nameField = BusinessSettingsViewController.field(String(localized: "Legal name"))
    private let vatField = BusinessSettingsViewController.field(String(localized: "VAT ID", comment: "Seller VAT identifier, EN 16931 BT-31"))
    private let regField = BusinessSettingsViewController.field(String(localized: "Company registration no.", comment: "Seller legal registration identifier, EN 16931 BT-30"))
    private let line1Field = BusinessSettingsViewController.field(String(localized: "Street address"))
    private let cityField = BusinessSettingsViewController.field(String(localized: "City"))
    private let postalField = BusinessSettingsViewController.field(String(localized: "Postal code"))
    private let countryField = BusinessSettingsViewController.field(String(localized: "Country code", comment: "ISO 3166 two-letter country code"))
    private let ibanField = BusinessSettingsViewController.field(String(localized: "IBAN", comment: "International Bank Account Number; keep the acronym"))
    private let bicField = BusinessSettingsViewController.field(String(localized: "BIC", comment: "Bank Identifier Code (SWIFT); keep the acronym"))
    private let peppolField = BusinessSettingsViewController.field(String(localized: "Your Peppol ID (scheme:id)", comment: "Placeholder for the seller Peppol participant identifier; \"scheme:id\" is literal syntax"))
    private let vatRateField = BusinessSettingsViewController.field(String(localized: "Default VAT %"), keyboard: .decimalPad)
    private let termsField = BusinessSettingsViewController.field(String(localized: "Default payment terms"))
    private let peppolStatusLabel = UILabel()
    private let peppolFixButton = UIButton(type: .system)
    private var peppolSuggestion: PeppolID?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Business")
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
        vatRateField.text = DecimalInput.text(Decimal(profile.defaultVATRatePercent))
        termsField.text = profile.defaultPaymentTerms
        refreshPeppolAdvisory()
    }

    private func build() {
        peppolStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        peppolStatusLabel.textColor = DesignSystem.Color.secondary
        peppolStatusLabel.numberOfLines = 0
        peppolFixButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        peppolFixButton.contentHorizontalAlignment = .leading
        peppolFixButton.isHidden = true
        peppolFixButton.addAction(UIAction { [weak self] _ in self?.applyPeppolSuggestion() }, for: .touchUpInside)
        peppolField.addAction(UIAction { [weak self] _ in self?.refreshPeppolAdvisory() }, for: .editingChanged)
        countryField.addAction(UIAction { [weak self] _ in self?.refreshPeppolAdvisory() }, for: .editingDidEnd)
        vatField.addAction(UIAction { [weak self] _ in self?.refreshPeppolAdvisory() }, for: .editingDidEnd)
        regField.addAction(UIAction { [weak self] _ in self?.refreshPeppolAdvisory() }, for: .editingDidEnd)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [
            section(String(localized: "Identity")), nameField, vatField, regField,
            section(String(localized: "Address")), line1Field, cityField, postalField, countryField,
            section(String(localized: "Getting paid")), ibanField, bicField, peppolField, peppolStatusLabel, peppolFixButton,
            section(String(localized: "Defaults")), vatRateField, termsField,
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
        profile.defaultVATRatePercent = DecimalInput.parse(vatRateField.text).map { NSDecimalNumber(decimal: $0).doubleValue } ?? profile.defaultVATRatePercent
        profile.defaultPaymentTerms = termsField.text ?? ""
        AppSettings.defaultVATRatePercent = profile.defaultVATRatePercent
        let saved = profile
        navigationItem.rightBarButtonItem?.isEnabled = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await BusinessRepository.shared.save(saved)
                self.navigationController?.popViewController(animated: true)
            } catch {
                AppLogger.shared.error("business profile save failed: \(error)", category: .db)
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                let alert = UIAlertController(title: String(localized: "Couldn't Save"), message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    /// Always rewrites the seller's Peppol address from the field, so clearing it
    /// removes a stale endpoint instead of leaving one that would still be used
    /// for real delivery. A legacy Finnish `0037` OVT is upgraded to the mandated
    /// `0216` on save. Colon-less input clears the address (never blocks saving).
    private func applyPeppol(_ raw: String) {
        let input = raw.trimmed
        if input.contains(":") {
            let id = PeppolParticipant.normalized(PeppolID(parsing: input))
            profile.seller.peppolSchemeID = id.schemeID
            profile.seller.peppolEndpointID = id.endpointID
        } else {
            profile.seller.peppolSchemeID = ""
            profile.seller.peppolEndpointID = ""
        }
    }

    /// Live, country-aware guidance for the seller's own Peppol id. A Finnish
    /// business is steered toward its `0216` OVT — derived from the VAT ID or
    /// company registration number — with a one-tap fix. Advisory only.
    private func refreshPeppolAdvisory() {
        let raw = (peppolField.text ?? "").trimmed
        if !raw.isEmpty && !raw.contains(":") {
            setPeppolHint(String(localized: "Use scheme:id — the scheme is a 4-digit code, e.g. 0216:003712345678.",
                                 comment: "Peppol participant id format hint; \"scheme:id\" is literal syntax"),
                          warning: true, suggestion: nil)
            return
        }
        let id = PeppolID(parsing: raw)
        let advisory = PeppolParticipant.advisory(
            schemeID: id.schemeID, endpointID: id.endpointID,
            countryCode: countryField.text ?? "", vatID: vatField.text ?? "",
            businessID: regField.text ?? "")
        setPeppolHint(advisory?.message, warning: advisory?.level == .warning, suggestion: advisory?.suggestion)
    }

    private func setPeppolHint(_ text: String?, warning: Bool, suggestion: PeppolID?) {
        peppolStatusLabel.text = text
        peppolStatusLabel.textColor = warning ? DesignSystem.Color.overdue : DesignSystem.Color.secondary
        peppolSuggestion = suggestion
        peppolFixButton.isHidden = suggestion == nil
        if let suggestion { peppolFixButton.setTitle(String(localized: "Use \(suggestion.wire)", comment: "Button offering a corrected Peppol participant id"), for: .normal) }
    }

    private func applyPeppolSuggestion() {
        guard let suggestion = peppolSuggestion else { return }
        peppolField.text = suggestion.wire
        refreshPeppolAdvisory()
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

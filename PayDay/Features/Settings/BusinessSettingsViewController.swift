import UIKit
import PayDayKit

/// Edits the seller business profile and invoice defaults. Saved values pre-fill
/// every new document, so this is the one form that pays off on every invoice.
///
/// `.essentials` is the same form cut to what a first invoice needs — legal
/// name, country, IBAN — for onboarding and for the setup a new invoice routes
/// to while the seller is still the example business.
final class BusinessSettingsViewController: UIViewController {
    enum Mode { case settings, essentials }

    /// Called in `.essentials` once the user saves (`true`) or defers (`false`).
    var onFinish: ((_ saved: Bool) -> Void)?

    private var profile = BusinessProfile()
    private let mode: Mode

    private let nameField = BusinessSettingsViewController.field(String(localized: "Legal name"))
    private let vatField = BusinessSettingsViewController.field(String(localized: "VAT ID", comment: "Seller VAT identifier, EN 16931 BT-31"))
    private let regField = BusinessSettingsViewController.field(String(localized: "Company registration no.", comment: "Seller legal registration identifier, EN 16931 BT-30"))
    private let line1Field = BusinessSettingsViewController.field(String(localized: "Street address"))
    private let cityField = BusinessSettingsViewController.field(String(localized: "City"))
    private let postalField = BusinessSettingsViewController.field(String(localized: "Postal code"))
    private let countryField = BusinessSettingsViewController.field(String(localized: "Country code", comment: "ISO 3166 two-letter country code"))
    private lazy var ibanField = BusinessSettingsViewController.field(mode == .essentials
        ? String(localized: "IBAN (optional)", comment: "Placeholder for the seller's bank account during setup; keep the acronym")
        : String(localized: "IBAN", comment: "International Bank Account Number; keep the acronym"))
    private let countryButton = UIButton(type: .system)
    private let regionalDefaultsLabel = UILabel()
    private lazy var continueButton = DesignSystem.primaryButton(String(localized: "Continue"))
    private var selectedCountryCode = ""
    private let bicField = BusinessSettingsViewController.field(String(localized: "BIC", comment: "Bank Identifier Code (SWIFT); keep the acronym"))
    private let peppolField = BusinessSettingsViewController.field(String(localized: "Your Peppol ID (scheme:id)", comment: "Placeholder for the seller Peppol participant identifier; \"scheme:id\" is literal syntax"))
    private let vatRateField = BusinessSettingsViewController.field(String(localized: "Default VAT %"), keyboard: .decimalPad)
    private let termsField = BusinessSettingsViewController.field(String(localized: "Default payment terms"))
    private let peppolStatusLabel = UILabel()
    private let peppolFixButton = UIButton(type: .system)
    private var peppolSuggestion: PeppolID?
    private let focusesPeppol: Bool

    init(mode: Mode = .settings, focusesPeppol: Bool = false) {
        self.mode = mode
        self.focusesPeppol = focusesPeppol
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if focusesPeppol { peppolField.becomeFirstResponder() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = DesignSystem.Color.background
        switch mode {
        case .settings:
            title = String(localized: "Business")
            navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .save, primaryAction: UIAction { [weak self] _ in self?.commit() })
            build()
        case .essentials:
            buildEssentials()
        }
        load()
    }

    private func load() {
        Task {
            let loaded = (try? await BusinessRepository.shared.load()) ?? BusinessProfile()
            await MainActor.run { self.profile = Self.editable(loaded); self.populate() }
        }
    }

    /// The example business is never edited in place: the form starts blank, on
    /// the device region's defaults, so saving can't leave any of its details
    /// (VAT ID, IBAN, contact) on the user's invoices.
    private static func editable(_ loaded: BusinessProfile) -> BusinessProfile {
        guard loaded.isDemo else { return loaded }
        let region = DashboardViewModel.countryCode(for: nil)
        return RegionalDefaults.forCountry(region) == nil ? BusinessProfile() : .starting(in: region)
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
        if mode == .essentials { selectCountry(profile.seller.address.countryCode) }
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
        scroll.pinEdges(toSafeAreaOf: view)
        scroll.embedColumn(stack, maxWidth: ColumnWidth.form, insets: UIEdgeInsets(
            top: DesignSystem.Spacing.m, left: DesignSystem.Spacing.m,
            bottom: DesignSystem.Spacing.l, right: DesignSystem.Spacing.m))
    }

    private func commit() {
        guard mode == .settings else { return commitEssentials() }
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
        persist(profile) { [weak self] in self?.navigationController?.popViewController(animated: true) }
    }

    /// Saves the essentials over whatever was there — for the example business,
    /// the blank regional profile `editable` started from — so nothing of the
    /// example survives into the user's invoices.
    private func commitEssentials() {
        let name = (nameField.text ?? "").trimmed
        guard !name.isEmpty, !selectedCountryCode.isEmpty else { return }
        profile.seller.legalName = name
        profile.applyRegionalDefaults(for: selectedCountryCode)
        let iban = PaymentMeans(iban: ibanField.text ?? "").normalizedIBAN
        profile.paymentMeans = PaymentMeans(method: .creditTransfer, iban: iban,
                                            bic: iban.isEmpty ? "" : profile.paymentMeans.bic, accountName: name)
        AppSettings.defaultVATRatePercent = profile.defaultVATRatePercent
        AppSettings.defaultCurrencyCode = profile.defaultCurrencyCode
        AppSettings.defaultEInvoiceProfile = profile.defaultEInvoiceProfile.rawValue
        persist(profile) { [weak self] in
            AppLogger.shared.info("business essentials saved (\(self?.selectedCountryCode ?? ""))", category: .ui)
            self?.onFinish?(true)
        }
    }

    private func persist(_ saved: BusinessProfile, then done: @escaping @MainActor () -> Void) {
        setSaving(true)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await BusinessRepository.shared.save(saved)
                done()
            } catch {
                AppLogger.shared.error("business profile save failed: \(error)", category: .db)
                self.setSaving(false)
                let alert = UIAlertController(title: String(localized: "Couldn't Save"), message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func setSaving(_ saving: Bool) {
        navigationItem.rightBarButtonItem?.isEnabled = !saving
        continueButton.isEnabled = !saving && canContinue
    }

    private var canContinue: Bool {
        !(nameField.text ?? "").trimmed.isEmpty && !selectedCountryCode.isEmpty
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

    private func buildEssentials() {
        let heading = DesignSystem.label(String(localized: "Your business"), font: DesignSystem.Typography.largeTitle())
        let intro = DesignSystem.label(
            String(localized: "Your name and bank account go on every invoice you send. Add your VAT ID, address and Peppol ID any time in Settings.",
                   comment: "Business setup intro during onboarding"),
            font: DesignSystem.Typography.body(), color: DesignSystem.Color.secondary)

        nameField.textContentType = .organizationName
        nameField.returnKeyType = .next
        nameField.addAction(UIAction { [weak self] _ in self?.refreshContinue() }, for: .editingChanged)
        nameField.addAction(UIAction { [weak self] _ in self?.ibanField.becomeFirstResponder() }, for: .editingDidEndOnExit)
        ibanField.autocapitalizationType = .allCharacters
        ibanField.autocorrectionType = .no
        ibanField.returnKeyType = .done
        ibanField.addAction(UIAction { [weak self] _ in self?.commit() }, for: .editingDidEndOnExit)

        configureCountryButton()
        regionalDefaultsLabel.font = DesignSystem.Typography.caption()
        regionalDefaultsLabel.adjustsFontForContentSizeCategory = true
        regionalDefaultsLabel.textColor = DesignSystem.Color.secondary
        regionalDefaultsLabel.numberOfLines = 0

        continueButton.addAction(UIAction { [weak self] _ in self?.commit() }, for: .touchUpInside)
        let later = UIButton(type: .system)
        later.setTitle(String(localized: "Set up later", comment: "Skips business setup; the dashboard keeps reminding"), for: .normal)
        later.titleLabel?.font = DesignSystem.Typography.scaledSystem(16, .medium, relativeTo: .callout)
        later.titleLabel?.adjustsFontForContentSizeCategory = true
        later.addAction(UIAction { [weak self] _ in
            AppLogger.shared.info("business setup deferred", category: .ui)
            self?.view.endEditing(true)
            self?.onFinish?(false)
        }, for: .touchUpInside)

        let fields = UIStackView(arrangedSubviews: [nameField, countryButton, regionalDefaultsLabel, ibanField])
        fields.axis = .vertical
        fields.spacing = DesignSystem.Spacing.s
        fields.setCustomSpacing(DesignSystem.Spacing.m, after: regionalDefaultsLabel)

        let stack = UIStackView(arrangedSubviews: [heading, intro, fields, continueButton, later])
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.l
        stack.setCustomSpacing(DesignSystem.Spacing.s, after: heading)
        stack.setCustomSpacing(DesignSystem.Spacing.s, after: continueButton)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        view.addSubview(scroll)
        scroll.pinEdges(toSafeAreaOf: view)
        scroll.embedColumn(stack, maxWidth: ColumnWidth.form, insets: UIEdgeInsets(
            top: DesignSystem.Spacing.m, left: DesignSystem.Spacing.l,
            bottom: DesignSystem.Spacing.l, right: DesignSystem.Spacing.l))
        refreshContinue()
    }

    /// A menu of every country Pay Day has invoicing defaults for, by localized
    /// name; picking one re-derives the currency and VAT line beneath it.
    private func configureCountryButton() {
        var config = UIButton.Configuration.plain()
        config.background.backgroundColor = .systemBackground
        config.background.cornerRadius = 6
        config.background.strokeColor = .systemGray4
        config.background.strokeWidth = 1 / max(traitCollection.displayScale, 1)
        config.image = UIImage(systemName: "chevron.up.chevron.down")
        config.imagePlacement = .trailing
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 7, bottom: 7, trailing: 10)
        config.titleAlignment = .leading
        countryButton.configuration = config
        countryButton.contentHorizontalAlignment = .fill
        countryButton.showsMenuAsPrimaryAction = true
        countryButton.changesSelectionAsPrimaryAction = false
        selectCountry("")
    }

    private func countryMenu() -> UIMenu {
        let names = RegionalDefaults.supportedCountryCodes
            .map { (code: $0, name: MandateCopy.countryName($0, locale: .current)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return UIMenu(children: names.map { entry in
            UIAction(title: entry.name, state: entry.code == selectedCountryCode ? .on : .off) { [weak self] _ in
                self?.selectCountry(entry.code)
            }
        })
    }

    private func selectCountry(_ code: String) {
        let upper = code.trimmed.uppercased()
        selectedCountryCode = RegionalDefaults.forCountry(upper) == nil ? "" : upper
        let title = selectedCountryCode.isEmpty
            ? String(localized: "Choose your country", comment: "Country picker placeholder in business setup")
            : MandateCopy.countryName(selectedCountryCode, locale: .current)
        countryButton.configuration?.attributedTitle = AttributedString(
            title, attributes: AttributeContainer([.font: DesignSystem.Typography.body()]))
        countryButton.configuration?.baseForegroundColor = selectedCountryCode.isEmpty ? DesignSystem.Color.tertiary : DesignSystem.Color.label
        countryButton.menu = countryMenu()
        countryButton.accessibilityLabel = String(localized: "Country")
        countryButton.accessibilityValue = selectedCountryCode.isEmpty ? nil : title
        regionalDefaultsLabel.text = RegionalDefaults.forCountry(selectedCountryCode).map(Self.regionalDefaultsLine)
        regionalDefaultsLabel.isHidden = regionalDefaultsLabel.text == nil
        refreshContinue()
    }

    private static func regionalDefaultsLine(_ defaults: RegionalDefaults) -> String {
        let rate = (defaults.standardVATRatePercent / 100).formatted(.percent.precision(.fractionLength(0...1)))
        return String(localized: "Invoices in \(defaults.currencyCode) with \(rate) standard VAT. You can change both in Settings.",
                      comment: "Business setup: the defaults derived from the chosen country; a currency code and a percentage")
    }

    private func refreshContinue() {
        continueButton.isEnabled = canContinue
    }
}

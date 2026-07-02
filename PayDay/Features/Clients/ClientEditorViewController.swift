import UIKit
import PayDayKit

/// Create or edit a client, including the VAT id (with a live VIES check) and
/// the Peppol participant id needed for network delivery.
final class ClientEditorViewController: UIViewController {
    private var party: Party
    private let onSave: (Party) -> Void
    private let vatService = VATValidationService()

    private let nameField = ClientEditorViewController.field("Legal name")
    private let emailField = ClientEditorViewController.field("Email", keyboard: .emailAddress)
    private let line1Field = ClientEditorViewController.field("Street address")
    private let cityField = ClientEditorViewController.field("City")
    private let postalField = ClientEditorViewController.field("Postal code")
    private let countryField = ClientEditorViewController.field("Country code (e.g. DE)")
    private let vatField = ClientEditorViewController.field("VAT ID (e.g. DE123456789)")
    private let peppolField = ClientEditorViewController.field("Peppol ID (scheme:id)")
    private let vatStatusLabel = UILabel()
    private let peppolStatusLabel = UILabel()
    private let peppolFixButton = UIButton(type: .system)
    private var peppolSuggestion: PeppolID?

    init(party: Party?, onSave: @escaping (Party) -> Void) {
        self.party = party ?? Party(id: UUID().uuidString, legalName: "")
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Client"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = DesignSystem.Color.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .save, primaryAction: UIAction { [weak self] _ in self?.commit() })
        populate()
        build()
        configureFieldChaining()
        peppolField.addAction(UIAction { [weak self] _ in self?.refreshPeppolAdvisory() }, for: .editingChanged)
        countryField.addAction(UIAction { [weak self] _ in self?.refreshPeppolAdvisory() }, for: .editingDidEnd)
        vatField.addAction(UIAction { [weak self] _ in self?.refreshPeppolAdvisory() }, for: .editingDidEnd)
        refreshPeppolAdvisory()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if nameField.text?.isEmpty ?? true { nameField.becomeFirstResponder() }
    }

    private var orderedFields: [UITextField] {
        [nameField, emailField, line1Field, cityField, postalField, countryField, vatField, peppolField]
    }

    private func configureFieldChaining() {
        let fields = orderedFields
        for (i, field) in fields.enumerated() {
            field.delegate = self
            field.returnKeyType = i == fields.count - 1 ? .done : .next
        }
    }

    private func populate() {
        nameField.text = party.legalName
        emailField.text = party.email
        line1Field.text = party.address.line1
        cityField.text = party.address.city
        postalField.text = party.address.postalCode
        countryField.text = party.address.countryCode
        vatField.text = party.vatID
        peppolField.text = party.peppolEndpointID.isEmpty ? "" : "\(party.peppolSchemeID):\(party.peppolEndpointID)"
        vatField.addAction(UIAction { [weak self] _ in self?.checkVAT() }, for: .editingDidEnd)
    }

    private func build() {
        vatStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        vatStatusLabel.textColor = DesignSystem.Color.secondary
        peppolStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        peppolStatusLabel.textColor = DesignSystem.Color.secondary
        peppolStatusLabel.numberOfLines = 0
        peppolFixButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        peppolFixButton.contentHorizontalAlignment = .leading
        peppolFixButton.isHidden = true
        peppolFixButton.addAction(UIAction { [weak self] _ in self?.applyPeppolSuggestion() }, for: .touchUpInside)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [
            nameField, emailField, line1Field, cityField, postalField, countryField, vatField, vatStatusLabel, peppolField, peppolStatusLabel, peppolFixButton,
        ])
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.m
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        scroll.pinEdges(toSafeAreaOf: view)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: DesignSystem.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: DesignSystem.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -DesignSystem.Spacing.m),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -DesignSystem.Spacing.l),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -DesignSystem.Spacing.m * 2),
        ])
    }

    private func checkVAT() {
        let vatID = vatField.text ?? ""
        guard !vatID.isEmpty else { vatStatusLabel.text = nil; return }
        vatStatusLabel.text = "Checking VAT…"
        Task { [weak self] in
            let result = try? await self?.vatService.validate(vatID: vatID)
            await MainActor.run {
                guard let self else { return }
                guard let result else { self.vatStatusLabel.text = nil; return }
                if !result.reachable {
                    self.vatStatusLabel.text = "Couldn't reach VIES — you can still issue."
                    self.vatStatusLabel.textColor = DesignSystem.Color.secondary
                } else if result.valid {
                    self.vatStatusLabel.text = "✓ Valid VAT number" + (result.name.map { " · \($0)" } ?? "")
                    self.vatStatusLabel.textColor = DesignSystem.Color.paid
                } else {
                    self.vatStatusLabel.text = "✗ Not a valid VAT number"
                    self.vatStatusLabel.textColor = DesignSystem.Color.overdue
                }
            }
        }
    }

    private func commit() {
        party.legalName = nameField.text ?? ""
        party.email = (emailField.text ?? "").normalizedEmail
        party.address = PostalAddress(
            line1: line1Field.text ?? "", city: cityField.text ?? "",
            postalCode: postalField.text ?? "", countryCode: countryField.text ?? "")
        party.vatID = (vatField.text ?? "").normalizedVATID
        applyPeppol(peppolField.text ?? "", into: &party)
        let saved = party
        Task { [weak self] in
            try? await ClientRepository.shared.save(saved)
            await MainActor.run {
                guard let self else { return }
                self.onSave(saved)
                self.navigationController?.popViewController(animated: true)
            }
        }
    }

    /// Always rewrites the party's Peppol address from the field, so clearing it
    /// removes a stale endpoint instead of leaving one that would still be used
    /// for real delivery. A legacy Finnish `0037` OVT is upgraded to the mandated
    /// `0216` on save. Colon-less input clears the address (never blocks saving).
    private func applyPeppol(_ raw: String, into party: inout Party) {
        let input = raw.trimmed
        if input.contains(":") {
            let id = PeppolParticipant.normalized(PeppolID(parsing: input))
            party.peppolSchemeID = id.schemeID
            party.peppolEndpointID = id.endpointID
        } else {
            party.peppolSchemeID = ""
            party.peppolEndpointID = ""
        }
    }

    /// Live, country-aware guidance for the Peppol field — for Finnish parties it
    /// steers a blank/legacy/malformed id toward a `0216` OVT and offers the
    /// corrected value as a one-tap fix. Purely advisory; never blocks saving.
    private func refreshPeppolAdvisory() {
        let raw = (peppolField.text ?? "").trimmed
        if !raw.isEmpty && !raw.contains(":") {
            setPeppolHint("Use scheme:id — the scheme is a 4-digit code, e.g. 0216:003712345678.", warning: true, suggestion: nil)
            return
        }
        let id = PeppolID(parsing: raw)
        let advisory = PeppolParticipant.advisory(
            schemeID: id.schemeID, endpointID: id.endpointID,
            countryCode: countryField.text ?? "", vatID: vatField.text ?? "",
            businessID: party.legalRegistrationID)
        setPeppolHint(advisory?.message, warning: advisory?.level == .warning, suggestion: advisory?.suggestion)
    }

    private func setPeppolHint(_ text: String?, warning: Bool, suggestion: PeppolID?) {
        peppolStatusLabel.text = text
        peppolStatusLabel.textColor = warning ? DesignSystem.Color.overdue : DesignSystem.Color.secondary
        peppolSuggestion = suggestion
        peppolFixButton.isHidden = suggestion == nil
        if let suggestion { peppolFixButton.setTitle("Use \(suggestion.wire)", for: .normal) }
    }

    private func applyPeppolSuggestion() {
        guard let suggestion = peppolSuggestion else { return }
        peppolField.text = suggestion.wire
        refreshPeppolAdvisory()
    }

    private static func field(_ placeholder: String, keyboard: UIKeyboardType = .default) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.keyboardType = keyboard
        field.autocapitalizationType = keyboard == .emailAddress ? .none : .words
        field.font = DesignSystem.Typography.body()
        field.adjustsFontForContentSizeCategory = true
        return field
    }
}

extension ClientEditorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let fields = orderedFields
        if let i = fields.firstIndex(of: textField), i + 1 < fields.count {
            fields[i + 1].becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
            commit()
        }
        return true
    }
}

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
        view.backgroundColor = DesignSystem.Color.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .save, primaryAction: UIAction { [weak self] _ in self?.commit() })
        populate()
        build()
        configureFieldChaining()
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
        peppolField.text = party.peppolEndpointID.isEmpty ? "" : "\(party.peppolSchemeID):\(party.peppolEndpointID.components(separatedBy: ":").last ?? "")"
        vatField.addAction(UIAction { [weak self] _ in self?.checkVAT() }, for: .editingDidEnd)
    }

    private func build() {
        vatStatusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        vatStatusLabel.textColor = DesignSystem.Color.secondary

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [
            nameField, emailField, line1Field, cityField, postalField, countryField, vatField, vatStatusLabel, peppolField,
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
        party.email = emailField.text ?? ""
        party.address = PostalAddress(
            line1: line1Field.text ?? "", city: cityField.text ?? "",
            postalCode: postalField.text ?? "", countryCode: countryField.text ?? "")
        party.vatID = vatField.text ?? ""
        if let peppol = peppolField.text, peppol.contains(":") {
            party.peppolSchemeID = String(peppol.prefix(while: { $0 != ":" }))
            party.peppolEndpointID = peppol
        }
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

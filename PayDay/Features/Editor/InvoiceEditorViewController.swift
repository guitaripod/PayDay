import Combine
import PhotosUI
import UIKit
import PayDayKit

/// Builds/edits a document. A grouped table form with live totals in the footer
/// and a Preview action that renders the PDF and (for Pro) the e-invoice.
final class InvoiceEditorViewController: UIViewController {
    private enum Section: Int, CaseIterable { case details, client, lines, notes }

    private let viewModel: InvoiceEditorViewModel
    private var cancellables = Set<AnyCancellable>()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let totalsBar = TotalsBarView()

    private var invoice: Invoice?
    private var totals: ComputedTotals?
    private var issues: [ValidationIssue] = []

    init(viewModel: InvoiceEditorViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        title = viewModel.isNew ? "New" : "Edit"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Preview", primaryAction: UIAction { [weak self] _ in self?.preview() })
        setupLayout()
        bind()
        viewModel.start()
    }

    private func setupLayout() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        totalsBar.translatesAutoresizingMaskIntoConstraints = false
        totalsBar.onSave = { [weak self] in self?.viewModel.save() }
        view.addSubview(tableView)
        view.addSubview(totalsBar)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: totalsBar.topAnchor),
            totalsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            totalsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            totalsBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func bind() {
        viewModel.invoicePublisher.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.invoice = $0; self?.tableView.reloadData() }
            .store(in: &cancellables)
        viewModel.totalsPublisher.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.totals = $0; self?.totalsBar.update(totals: $0) }
            .store(in: &cancellables)
        viewModel.validationPublisher.receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.issues = $0; self?.totalsBar.update(issues: $0) }
            .store(in: &cancellables)
        viewModel.savedPublisher.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.navigationController?.popViewController(animated: true) }
            .store(in: &cancellables)
    }

    private func preview() {
        guard let invoice else { return }
        viewModel.save()
        let previewVC = InvoicePreviewViewController(invoice: invoice)
        navigationController?.pushViewController(previewVC, animated: true)
    }

    private func editClient() {
        let picker = ClientListViewController(selection: { [weak self] party in
            self?.viewModel.setBuyer(party)
            self?.navigationController?.popViewController(animated: true)
        })
        navigationController?.pushViewController(picker, animated: true)
    }

    private func editLine(_ line: LineItem?) {
        let model = line ?? viewModel.newLineTemplate()
        let editor = LineItemEditorViewController(
            line: model,
            currency: invoice?.currency ?? .eur,
            onSave: { [weak self] in self?.viewModel.upsert($0) },
            onDelete: line == nil ? nil : { [weak self] in self?.viewModel.removeLine(id: model.id) })
        let nav = UINavigationController(rootViewController: editor)
        present(nav, animated: true)
    }

    private func aiAssist() {
        let sheet = UIAlertController(title: "Draft line items", message: "Pay Day turns words or a photo into billable lines.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Describe in words", style: .default) { [weak self] _ in self?.aiFromText() })
        sheet.addAction(UIAlertAction(title: "Scan a photo or receipt", style: .default) { [weak self] _ in self?.aiFromPhoto() })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        present(sheet, animated: true)
    }

    private func aiFromText() {
        let alert = UIAlertController(title: "Describe the work", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "8h design at €90, plus €200 hosting" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Draft", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text, !text.isEmpty else { return }
            self?.runDraft { service, currency in try await service.lineItems(fromText: text, currency: currency) }
        })
        present(alert, animated: true)
    }

    private func aiFromPhoto() {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func runDraft(_ work: @escaping (InvoiceAIService, Currency) async throws -> [InvoiceAIService.DraftedLine]) {
        let currency = invoice?.currency ?? .eur
        Task {
            do {
                let drafts = try await work(InvoiceAIService(), currency)
                if drafts.isEmpty {
                    presentInfo("Nothing found", "Couldn't extract line items — try describing them instead.")
                } else {
                    viewModel.appendDraftedLines(drafts)
                }
            } catch {
                presentInfo("Couldn't draft", "The AI request failed. Check your connection or credits.")
            }
        }
    }

    private func presentInfo(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension InvoiceEditorViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            guard let image = object as? UIImage,
                  let base64 = Self.downscaledJPEGBase64(image) else { return }
            Task { @MainActor in
                self?.runDraft { service, currency in try await service.lineItems(fromImageBase64: base64, currency: currency) }
            }
        }
    }

    /// Downscale to keep the upload small and the vision cost bounded.
    private static func downscaledJPEGBase64(_ image: UIImage, maxDimension: CGFloat = 1536) -> String? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}

extension InvoiceEditorViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .details: return "Details"
        case .client: return "Bill to"
        case .lines: return "Line items"
        case .notes: return "Notes & terms"
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .details: return 3
        case .client: return 1
        case .lines: return (invoice?.lines.count ?? 0) + 2
        case .notes: return 2
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .none
        cell.selectionStyle = .default
        guard let invoice else { cell.contentConfiguration = config; return cell }

        switch Section(rawValue: indexPath.section)! {
        case .details:
            switch indexPath.row {
            case 0: config.text = "Number"; config.secondaryText = invoice.number
            case 1: config.text = "Issued"; config.secondaryText = Format.date(invoice.issueDate)
            default: config.text = "Due"; config.secondaryText = Format.date(invoice.dueDate)
            }
        case .client:
            config.text = invoice.buyer.legalName.isEmpty ? "Select a client" : invoice.buyer.displayName
            if !invoice.buyer.address.singleLine.isEmpty { config.secondaryText = invoice.buyer.address.singleLine }
            cell.accessoryType = .disclosureIndicator
        case .lines:
            let lineCount = invoice.lines.count
            if indexPath.row < lineCount {
                let line = invoice.lines[indexPath.row]
                let net = invoice.totals().lineNets[indexPath.row]
                config.text = line.name.isEmpty ? "Untitled" : line.name
                config.secondaryText = Format.money(net)
                cell.accessoryType = .disclosureIndicator
            } else if indexPath.row == lineCount {
                config.text = "Add line item"
                config.image = UIImage(systemName: "plus.circle.fill")
                config.imageProperties.tintColor = DesignSystem.Color.accent
            } else {
                config.text = "Draft with AI"
                config.image = UIImage(systemName: "sparkles")
                config.imageProperties.tintColor = DesignSystem.Color.accent
            }
        case .notes:
            if indexPath.row == 0 {
                config.text = "Payment terms"; config.secondaryText = invoice.paymentTerms.isEmpty ? "None" : invoice.paymentTerms
            } else {
                config.text = "Note"; config.secondaryText = invoice.note.isEmpty ? "None" : invoice.note
            }
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let invoice else { return }
        switch Section(rawValue: indexPath.section)! {
        case .details: editDetail(row: indexPath.row)
        case .client: editClient()
        case .lines:
            let count = invoice.lines.count
            if indexPath.row < count { editLine(invoice.lines[indexPath.row]) }
            else if indexPath.row == count { editLine(nil) }
            else { aiAssist() }
        case .notes: editNote(row: indexPath.row)
        }
    }

    private func editDetail(row: Int) {
        switch row {
        case 0: promptText(title: "Invoice number", value: invoice?.number ?? "") { [weak self] in self?.viewModel.setNumber($0) }
        case 1: promptDate(title: "Issue date", value: invoice?.issueDate) { [weak self] in self?.viewModel.setIssueDate($0) }
        default: promptDate(title: "Due date", value: invoice?.dueDate) { [weak self] in self?.viewModel.setDueDate($0) }
        }
    }

    private func editNote(row: Int) {
        if row == 0 {
            promptText(title: "Payment terms", value: invoice?.paymentTerms ?? "") { [weak self] in self?.viewModel.setPaymentTerms($0) }
        } else {
            promptText(title: "Note", value: invoice?.note ?? "") { [weak self] in self?.viewModel.setNote($0) }
        }
    }

    private func promptText(title: String, value: String, onSave: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = value }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in onSave(alert.textFields?.first?.text ?? "") })
        present(alert, animated: true)
    }

    private func promptDate(title: String, value: CalendarDate?, onSave: @escaping (CalendarDate) -> Void) {
        let picker = DatePickerSheetViewController(title: title, date: value ?? Format.today(), onPick: onSave)
        present(UINavigationController(rootViewController: picker), animated: true)
    }
}

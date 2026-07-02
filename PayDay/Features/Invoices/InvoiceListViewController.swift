import Combine
import UIKit
import PayDayKit

final class InvoiceCell: UITableViewCell {
    static let reuseID = "InvoiceCell"

    private let row = InvoiceRowView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundConfiguration = .clear()
        selectionStyle = .none
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        row.pinEdges(to: contentView, insets: UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func configure(with invoice: Invoice) {
        row.update(with: invoice)
    }
}

final class InvoiceListViewController: UIViewController {
    private let viewModel: InvoiceListViewModel
    private var cancellables = Set<AnyCancellable>()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var emptyView: UIView?
    private var documents: [Invoice] = []
    private var renderedKind: DocumentType

    private lazy var dataSource = UITableViewDiffableDataSource<Int, Invoice.ID>(tableView: tableView) { [weak self] tableView, indexPath, id in
        let cell = tableView.dequeueReusableCell(withIdentifier: InvoiceCell.reuseID, for: indexPath)
        guard let self,
              let invoiceCell = cell as? InvoiceCell,
              let invoice = self.documents.first(where: { $0.id == id }) else { return cell }
        invoiceCell.configure(with: invoice)
        invoiceCell.accessibilityCustomActions = self.accessibilityActions(for: invoice)
        return invoiceCell
    }

    init(kind: DocumentType) {
        self.viewModel = InvoiceListViewModel(kind: kind)
        self.renderedKind = kind
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private let kindControl = UISegmentedControl(items: ["Invoices", "Estimates"])

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .add, menu: UIMenu(children: [
            UIAction(title: "New Invoice", image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.create(.invoice) },
            UIAction(title: "New Estimate", image: UIImage(systemName: "doc.plaintext")) { [weak self] _ in self?.create(.estimate) },
        ]))
        kindControl.selectedSegmentIndex = viewModel.kind == .estimate ? 1 : 0
        kindControl.apportionsSegmentWidthsByContent = true
        kindControl.accessibilityLabel = "Document type"
        kindControl.addAction(UIAction { [weak self] _ in self?.switchKind() }, for: .valueChanged)
        navigationItem.titleView = kindControl
        setupTable()
        setupEmpty()
        bind()
    }

    private func switchKind() {
        viewModel.kind = kindControl.selectedSegmentIndex == 1 ? .estimate : .invoice
        title = viewModel.kind == .estimate ? "Estimates" : "Invoices"
        setupEmpty()
        viewModel.load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.register(InvoiceCell.self, forCellReuseIdentifier: InvoiceCell.reuseID)
        tableView.rowHeight = 68
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in self?.viewModel.load() }, for: .valueChanged)
        tableView.refreshControl = refresh
        view.addSubview(tableView)
        tableView.pinEdges(to: view)
        dataSource.defaultRowAnimation = .fade
    }

    private func setupEmpty() {
        emptyView?.removeFromSuperview()
        let isEstimate = viewModel.kind == .estimate
        let kind = viewModel.kind
        let empty = DesignSystem.emptyState(
            symbol: isEstimate ? "doc.plaintext" : "doc.text.badge.plus",
            title: "No \(viewModel.kind.noun)s yet",
            subtitle: isEstimate
                ? "Create an estimate to send a quote — convert it to an invoice when it's accepted."
                : "Create your first invoice. It's free, unlimited, and ready for EU e-invoicing.",
            ctaTitle: "Create \(viewModel.kind.noun)",
            ctaAction: { [weak self] in self?.create(kind) })
        empty.translatesAutoresizingMaskIntoConstraints = false
        empty.isHidden = true
        view.addSubview(empty)
        NSLayoutConstraint.activate([
            empty.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            empty.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            empty.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
        ])
        emptyView = empty
    }

    private func bind() {
        viewModel.documentsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] documents in
                self?.apply(documents)
            }
            .store(in: &cancellables)
        viewModel.errorPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.presentError(message) }
            .store(in: &cancellables)
    }

    /// Diffs the new documents into the table: inserts/deletes/moves animate,
    /// rows whose content changed are reconfigured in place, and a segment
    /// switch between kinds applies without animation so an invoices→estimates
    /// swap never plays as a misleading row-by-row diff.
    private func apply(_ newDocuments: [Invoice]) {
        let previousByID = Dictionary(documents.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let kindChanged = renderedKind != viewModel.kind
        renderedKind = viewModel.kind
        documents = newDocuments
        emptyView?.isHidden = !newDocuments.isEmpty
        tableView.refreshControl?.endRefreshing()

        var snapshot = NSDiffableDataSourceSnapshot<Int, Invoice.ID>()
        snapshot.appendSections([0])
        snapshot.appendItems(newDocuments.map(\.id))
        let changed = newDocuments.compactMap { invoice -> Invoice.ID? in
            guard let old = previousByID[invoice.id], old != invoice else { return nil }
            return invoice.id
        }
        snapshot.reconfigureItems(changed)
        let animated = !kindChanged && tableView.window != nil
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func presentError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func create(_ kind: DocumentType) {
        Haptics.tap()
        if kind != viewModel.kind {
            viewModel.kind = kind
            kindControl.selectedSegmentIndex = kind == .estimate ? 1 : 0
            title = kind == .estimate ? "Estimates" : "Invoices"
        }
        let editor = InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(kind: kind))
        navigationController?.pushViewController(editor, animated: true)
    }

    private func open(_ invoice: Invoice) {
        let editor = InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(existing: invoice))
        navigationController?.pushViewController(editor, animated: true)
    }

    private func invoice(at indexPath: IndexPath) -> Invoice? {
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return nil }
        return documents.first { $0.id == id }
    }
}

extension InvoiceListViewController: UITableViewDelegate {
    /// VoiceOver mirror of the swipe/context actions, which are otherwise unreachable.
    private func accessibilityActions(for invoice: Invoice) -> [UIAccessibilityCustomAction] {
        var actions: [UIAccessibilityCustomAction] = []
        if let primary = primaryAction(for: invoice) {
            let title = primary.title == "Invoice" ? "Convert to Invoice" : primary.title
            actions.append(UIAccessibilityCustomAction(name: title) { _ in primary.run(); return true })
        }
        if let sent = sentAction(for: invoice) {
            actions.append(UIAccessibilityCustomAction(name: sent.title) { _ in sent.run(); return true })
        }
        actions.append(UIAccessibilityCustomAction(name: "Duplicate") { [weak self] _ in self?.duplicate(invoice); return true })
        actions.append(UIAccessibilityCustomAction(name: "Delete") { [weak self] _ in self?.remove(invoice); return true })
        return actions
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let invoice = invoice(at: indexPath) else { return }
        open(invoice)
    }

    private func markPaid(_ invoice: Invoice) { Haptics.success(); viewModel.markPaid(invoice) }
    private func markSent(_ invoice: Invoice) { Haptics.success(); viewModel.markSent(invoice) }
    private func convert(_ invoice: Invoice) { Haptics.success(); viewModel.convertToInvoice(invoice) }
    private func duplicate(_ invoice: Invoice) { Haptics.tap(); viewModel.duplicate(invoice) }
    private func remove(_ invoice: Invoice) { Haptics.warning(); viewModel.delete(invoice) }

    /// The natural "primary" gesture per document type: pay an invoice, convert an estimate.
    private func primaryAction(for invoice: Invoice) -> (title: String, symbol: String, color: UIColor, run: () -> Void)? {
        if invoice.type == .invoice && invoice.status != .paid {
            return ("Mark Paid", "checkmark.circle.fill", DesignSystem.Color.paid, { [weak self] in self?.markPaid(invoice) })
        }
        if invoice.type == .estimate {
            return ("Invoice", "arrow.right.circle.fill", DesignSystem.Color.accent, { [weak self] in self?.convert(invoice) })
        }
        return nil
    }

    private func sentAction(for invoice: Invoice) -> (title: String, symbol: String, color: UIColor, run: () -> Void)? {
        guard invoice.type == .invoice, invoice.status == .draft else { return nil }
        return ("Mark Sent", "paperplane.fill", DesignSystem.Color.sent, { [weak self] in self?.markSent(invoice) })
    }

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let invoice = invoice(at: indexPath) else { return nil }
        var actions: [UIContextualAction] = []
        if let primary = primaryAction(for: invoice) {
            let action = UIContextualAction(style: .normal, title: primary.title) { _, _, done in primary.run(); done(true) }
            action.image = UIImage(systemName: primary.symbol)
            action.backgroundColor = primary.color
            actions.append(action)
        }
        if let sent = sentAction(for: invoice) {
            let action = UIContextualAction(style: .normal, title: sent.title) { _, _, done in sent.run(); done(true) }
            action.image = UIImage(systemName: sent.symbol)
            action.backgroundColor = sent.color
            actions.append(action)
        }
        guard !actions.isEmpty else { return nil }
        let config = UISwipeActionsConfiguration(actions: actions)
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard let invoice = invoice(at: indexPath) else { return nil }
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.remove(invoice); done(true)
        }
        let duplicate = UIContextualAction(style: .normal, title: "Duplicate") { [weak self] _, _, done in
            self?.duplicate(invoice); done(true)
        }
        duplicate.backgroundColor = DesignSystem.Color.sent
        return UISwipeActionsConfiguration(actions: [delete, duplicate])
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let invoice = invoice(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var children: [UIMenuElement] = [
                UIAction(title: "Open", image: UIImage(systemName: "doc.text")) { _ in self.open(invoice) },
                UIAction(title: "Duplicate", image: UIImage(systemName: "plus.square.on.square")) { _ in self.duplicate(invoice) },
            ]
            if let primary = self.primaryAction(for: invoice) {
                children.append(UIAction(title: primary.title == "Invoice" ? "Convert to Invoice" : primary.title,
                                         image: UIImage(systemName: primary.symbol)) { _ in primary.run() })
            }
            if let sent = self.sentAction(for: invoice) {
                children.append(UIAction(title: sent.title, image: UIImage(systemName: sent.symbol)) { _ in sent.run() })
            }
            children.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in self.remove(invoice) })
            return UIMenu(children: children)
        }
    }
}

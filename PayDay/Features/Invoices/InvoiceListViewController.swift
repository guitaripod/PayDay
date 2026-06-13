import Combine
import UIKit
import PayDayKit

final class InvoiceListViewController: UIViewController {
    private let viewModel: InvoiceListViewModel
    private var cancellables = Set<AnyCancellable>()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private var documents: [Invoice] = []

    init(kind: DocumentType) {
        self.viewModel = InvoiceListViewModel(kind: kind)
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
        kindControl.addAction(UIAction { [weak self] _ in self?.switchKind() }, for: .valueChanged)
        navigationItem.titleView = kindControl
        setupTable()
        setupEmpty()
        bind()
    }

    private func switchKind() {
        viewModel.kind = kindControl.selectedSegmentIndex == 1 ? .estimate : .invoice
        title = viewModel.kind == .estimate ? "Estimates" : "Invoices"
        viewModel.load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
    }

    private func setupTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.rowHeight = 68
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in self?.viewModel.load() }, for: .valueChanged)
        tableView.refreshControl = refresh
        view.addSubview(tableView)
        tableView.pinEdges(to: view)
    }

    private func setupEmpty() {
        emptyLabel.text = "No \(viewModel.kind.noun)s yet.\nTap + to create one."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = DesignSystem.Typography.body()
        emptyLabel.textColor = DesignSystem.Color.secondary
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    private func bind() {
        viewModel.documentsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] documents in
                self?.documents = documents
                self?.emptyLabel.isHidden = !documents.isEmpty
                self?.tableView.refreshControl?.endRefreshing()
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
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
}

extension InvoiceListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        documents.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.contentConfiguration = nil
        cell.backgroundConfiguration = .clear()
        cell.selectionStyle = .none
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        guard indexPath.row < documents.count else { return cell }
        let invoice = documents[indexPath.row]
        let row = InvoiceRowView(invoice: invoice) {}
        // The cell owns the tap (didSelectRow) and swipe actions; the embedded
        // control must not intercept touches or it double-pushes / eats swipes.
        row.isUserInteractionEnabled = false
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(row)
        row.pinEdges(to: cell.contentView, insets: UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.row < documents.count else { return }
        open(documents[indexPath.row])
    }

    // MARK: shared actions (used by swipe + context menu)

    private func markPaid(_ invoice: Invoice) { Haptics.success(); viewModel.markPaid(invoice) }
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

    func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.row < documents.count, let primary = primaryAction(for: documents[indexPath.row]) else { return nil }
        let action = UIContextualAction(style: .normal, title: primary.title) { _, _, done in primary.run(); done(true) }
        action.image = UIImage(systemName: primary.symbol)
        action.backgroundColor = primary.color
        let config = UISwipeActionsConfiguration(actions: [action])
        config.performsFirstActionWithFullSwipe = true
        return config
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.row < documents.count else { return nil }
        let invoice = documents[indexPath.row]
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
        guard indexPath.row < documents.count else { return nil }
        let invoice = documents[indexPath.row]
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
            children.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in self.remove(invoice) })
            return UIMenu(children: children)
        }
    }
}

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
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .add, primaryAction: UIAction { [weak self] _ in self?.create() })
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
                self?.tableView.reloadData()
            }
            .store(in: &cancellables)
    }

    private func create() {
        let editor = InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(kind: viewModel.kind))
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
        let invoice = documents[indexPath.row]
        let row = InvoiceRowView(invoice: invoice) { [weak self] in self?.open(invoice) }
        row.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(row)
        row.pinEdges(to: cell.contentView, insets: UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        open(documents[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let invoice = documents[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.viewModel.delete(invoice); done(true)
        }
        let duplicate = UIContextualAction(style: .normal, title: "Duplicate") { [weak self] _, _, done in
            self?.viewModel.duplicate(invoice); done(true)
        }
        duplicate.backgroundColor = DesignSystem.Color.sent
        var actions = [delete, duplicate]
        if invoice.type == .invoice && invoice.status != .paid {
            let paid = UIContextualAction(style: .normal, title: "Mark Paid") { [weak self] _, _, done in
                self?.viewModel.markPaid(invoice); done(true)
            }
            paid.backgroundColor = DesignSystem.Color.paid
            actions.append(paid)
        }
        if invoice.type == .estimate {
            let convert = UIContextualAction(style: .normal, title: "→ Invoice") { [weak self] _, _, done in
                self?.viewModel.convertToInvoice(invoice); done(true)
            }
            convert.backgroundColor = DesignSystem.Color.accent
            actions.append(convert)
        }
        return UISwipeActionsConfiguration(actions: actions)
    }
}

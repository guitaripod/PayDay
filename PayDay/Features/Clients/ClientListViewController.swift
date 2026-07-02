import UIKit
import PayDayKit

/// Lists clients. When constructed with a `selection` handler it acts as a
/// picker for the invoice editor; otherwise it is the Clients tab.
final class ClientListViewController: UIViewController {
    private let selection: ((Party) -> Void)?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var clients: [Party] = []
    private var emptyView: UIView?

    init(selection: ((Party) -> Void)? = nil) {
        self.selection = selection
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = selection == nil ? "Clients" : "Choose client"
        view.backgroundColor = DesignSystem.Color.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .add, primaryAction: UIAction { [weak self] _ in self?.edit(nil) })
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.pinEdges(to: view)

        let empty = DesignSystem.emptyState(
            symbol: "person.crop.circle.badge.plus", title: "No clients yet",
            subtitle: "Add the businesses you invoice. Their VAT ID and Peppol address power compliant e-invoices.",
            ctaTitle: "Add client", ctaAction: { [weak self] in self?.edit(nil) })
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        Task {
            let loaded = (try? await ClientRepository.shared.all()) ?? []
            await MainActor.run {
                self.clients = loaded
                self.emptyView?.isHidden = !loaded.isEmpty
                self.tableView.reloadData()
            }
        }
    }

    private func edit(_ party: Party?) {
        let editor = ClientEditorViewController(party: party) { [weak self] _ in self?.reload() }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func remove(_ party: Party, done: ((Bool) -> Void)? = nil) {
        Haptics.warning()
        Task { @MainActor [weak self] in
            guard let self else { done?(false); return }
            do {
                try await ClientRepository.shared.delete(id: party.id)
                if let index = self.clients.firstIndex(where: { $0.id == party.id }) {
                    self.clients.remove(at: index)
                    self.tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
                }
                self.emptyView?.isHidden = !self.clients.isEmpty
                done?(true)
            } catch {
                AppLogger.shared.error("client delete failed: \(error)", category: .db)
                done?(false)
                let alert = UIAlertController(title: "Couldn't Delete", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func accessibilityActions(for party: Party) -> [UIAccessibilityCustomAction] {
        [UIAccessibilityCustomAction(name: "Delete") { [weak self] _ in self?.remove(party); return true }]
    }
}

extension ClientListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { clients.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        guard indexPath.row < clients.count else { return cell }
        let party = clients[indexPath.row]
        var config = cell.defaultContentConfiguration()
        config.text = party.displayName
        config.secondaryText = [party.address.countryCode, party.hasVATID ? party.vatID : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        cell.contentConfiguration = config
        cell.accessoryType = selection == nil ? .detailButton : .none
        cell.accessibilityCustomActions = accessibilityActions(for: party)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < clients.count else { return }
        let party = clients[indexPath.row]
        if let selection { selection(party) } else { edit(party) }
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard indexPath.row < clients.count else { return }
        edit(clients[indexPath.row])
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.row < clients.count else { return nil }
        let party = clients[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
            self?.remove(party, done: done)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

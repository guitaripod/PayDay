import UIKit
import PayDayKit

/// Lists clients. When constructed with a `selection` handler it acts as a
/// picker for the invoice editor; otherwise it is the Clients tab.
final class ClientListViewController: UIViewController {
    private let selection: ((Party) -> Void)?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var clients: [Party] = []

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
                self.tableView.reloadData()
            }
        }
    }

    private func edit(_ party: Party?) {
        let editor = ClientEditorViewController(party: party) { [weak self] _ in self?.reload() }
        navigationController?.pushViewController(editor, animated: true)
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
        let delete = UIContextualAction(style: .destructive, title: "Delete") { _, _, done in
            Task { try? await ClientRepository.shared.delete(id: party.id); done(true) }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

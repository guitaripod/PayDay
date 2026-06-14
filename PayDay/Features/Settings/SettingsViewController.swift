import Combine
import UIKit
import PayDayKit

/// Settings: business profile, defaults, appearance, Pro status, credit balance,
/// and the legal/support links App Review expects.
final class SettingsViewController: UIViewController {
    private enum Row { case business, payment, defaults, appearance, pro, credits, privacy, terms, support, deleteAccount }
    private let sections: [(String, [Row])] = [
        ("Your business", [.business, .payment, .defaults]),
        ("Pay Day Pro", [.pro, .credits]),
        ("App", [.appearance]),
        ("About", [.privacy, .terms, .support]),
        ("Account", [.deleteAccount]),
    ]

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private var cancellables = Set<AnyCancellable>()
    private var isPremium = false
    private var balance = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        view.backgroundColor = DesignSystem.Color.background
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        view.addSubview(tableView)
        tableView.pinEdges(to: view)
        bind()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await AICreditsManager.store.refreshPremium() }
        tableView.reloadData()
    }

    private func bind() {
        AICreditsManager.store.$isPremium
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isPremium = $0; self?.tableView.reloadData() }
            .store(in: &cancellables)
        AICreditsManager.store.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.balance = $0; self?.tableView.reloadData() }
            .store(in: &cancellables)
    }
}

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? { sections[section].0 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].1.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        var config = cell.defaultContentConfiguration()
        cell.accessoryType = .disclosureIndicator
        switch sections[indexPath.section].1[indexPath.row] {
        case .business: config.text = "Business details"; config.image = UIImage(systemName: "building.2")
        case .payment: config.text = "Payment & IBAN"; config.image = UIImage(systemName: "creditcard")
        case .defaults: config.text = "Invoice defaults"; config.image = UIImage(systemName: "slider.horizontal.3")
        case .appearance: config.text = "Appearance"; config.image = UIImage(systemName: "circle.lefthalf.filled")
        case .pro:
            config.text = isPremium ? "Pay Day Pro — Active" : "Upgrade to Pro"
            config.image = UIImage(systemName: isPremium ? "checkmark.seal.fill" : "seal")
            config.imageProperties.tintColor = DesignSystem.Color.accent
        case .credits:
            config.text = "Credits"; config.secondaryText = "\(balance)"
            config.image = UIImage(systemName: "bolt.fill")
            cell.accessoryType = .disclosureIndicator
        case .privacy: config.text = "Privacy Policy"; config.image = UIImage(systemName: "hand.raised")
        case .terms: config.text = "Terms of Use"; config.image = UIImage(systemName: "doc.text")
        case .support: config.text = "Support"; config.image = UIImage(systemName: "envelope")
        case .deleteAccount:
            config.text = "Delete account"
            config.textProperties.color = DesignSystem.Color.overdue
            config.image = UIImage(systemName: "trash")
            config.imageProperties.tintColor = DesignSystem.Color.overdue
            cell.accessoryType = .none
        }
        cell.contentConfiguration = config
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch sections[indexPath.section].1[indexPath.row] {
        case .business, .payment, .defaults:
            navigationController?.pushViewController(BusinessSettingsViewController(), animated: true)
        case .appearance: presentAppearance()
        case .pro:
            if !isPremium { present(UINavigationController(rootViewController: PaywallViewController()), animated: true) }
        case .credits:
            navigationController?.pushViewController(CreditsViewController(), animated: true)
        case .privacy: open("https://mako.midgarcorp.cc/privacy/payday")
        case .terms: open("https://mako.midgarcorp.cc/terms/payday")
        case .support: open("mailto:support@midgarcorp.cc")
        case .deleteAccount: confirmDeleteAccount()
        }
    }

    private func confirmDeleteAccount() {
        let alert = UIAlertController(
            title: "Delete account?",
            message: "This permanently deletes your account, credit balance, and every invoice, estimate, and client on this device. This cannot be undone.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete account", style: .destructive) { [weak self] _ in
            self?.performDeleteAccount()
        })
        present(alert, animated: true)
    }

    private func performDeleteAccount() {
        let progress = UIAlertController(title: "Deleting…", message: nil, preferredStyle: .alert)
        present(progress, animated: true)
        Task { [weak self] in
            do {
                try await AccountService.deleteAccount()
                progress.dismiss(animated: true) { self?.resetAfterDeletion() }
            } catch {
                progress.dismiss(animated: true) {
                    let fail = UIAlertController(title: "Couldn't delete account", message: error.localizedDescription, preferredStyle: .alert)
                    fail.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(fail, animated: true)
                }
            }
        }
    }

    private func resetAfterDeletion() {
        AppSettings.hasOnboarded = false
        Task { await AICreditsManager.store.bootstrap() }
        guard let window = view.window else { return }
        let onboarding = OnboardingViewController()
        onboarding.onFinish = { [weak onboarding] in
            AppSettings.hasOnboarded = true
            onboarding?.view.window?.rootViewController = RootViewController()
        }
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            window.rootViewController = onboarding
        }
    }

    private func presentAppearance() {
        let alert = UIAlertController(title: "Appearance", message: nil, preferredStyle: .actionSheet)
        for (title, mode) in [("System", AppearanceMode.system), ("Light", .light), ("Dark", .dark)] {
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                AppSettings.appearance = mode
                self.view.window?.overrideUserInterfaceStyle = UIUserInterfaceStyle(rawValue: mode.rawValue) ?? .unspecified
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }
}

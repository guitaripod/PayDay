import Combine
import MidgarPortal
import MidgarUI
import UIKit

/// Settings: the Midgar portal card on top of MidgarUI's settings list with Pay Day's sections, hosted as a child so
/// the screen can sit in the Settings split view's primary column. The sections hold the business profile, defaults,
/// appearance, Pro status, credit balance, and the legal/support links App Review expects.
///
/// Rows read their values when built, so a change is shown by building them again with ``refreshList()``.
final class SettingsViewController: UIViewController {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6779927672")!
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6779927672?action=write-review")!

    var isPremium = false
    var balance = 0
    private var cancellables = Set<AnyCancellable>()

    private lazy var list = MidgarSettingsViewController(
        title: String(localized: "Settings"),
        sections: makeSections(),
        portalCardView: MidgarEntryView(config: PayDayMidgar.shared.portalConfig),
        theme: .payDay
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Settings")
        view.backgroundColor = DesignSystem.Color.background
        embedList()
        bind()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Task { await AICreditsManager.store.refreshPremium() }
        refreshList()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        showBusinessDetailIfRoomForIt()
    }

    /// Builds every row again from the current state.
    func refreshList() {
        list.sections = makeSections()
    }

    private func embedList() {
        addChild(list)
        list.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(list.view)
        NSLayoutConstraint.activate([
            list.view.topAnchor.constraint(equalTo: view.topAnchor),
            list.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            list.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            list.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        list.didMove(toParent: self)
    }

    /// With room for a detail column, opens the business form beside the list so the column is never an empty page.
    private func showBusinessDetailIfRoomForIt() {
        guard let split = listDetailSplit, !split.isCollapsed, split.showsPlaceholder else { return }
        split.showDetail([BusinessSettingsViewController()], isAutomatic: true)
    }

    private func bind() {
        AICreditsManager.store.$isPremium
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.isPremium = $0; self?.refreshList() }
            .store(in: &cancellables)
        AICreditsManager.store.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.balance = $0; self?.refreshList() }
            .store(in: &cancellables)
    }
}

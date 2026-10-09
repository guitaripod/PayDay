import Combine
import UIKit
import PayDayKit

/// The home screen: outstanding receivables headline, quick actions, and a few
/// recent documents. Binds to its view model via the `PassthroughSubject` seam.
final class DashboardViewController: UIViewController {
    private let viewModel: DashboardViewModel
    private var cancellables = Set<AnyCancellable>()

    private let scrollView = UIScrollView()
    private let columns = UIView()
    private let summaryColumn = UIStackView()
    private let recentColumn = UIStackView()
    private var summaryWidth = NSLayoutConstraint()
    private var columnGap = NSLayoutConstraint()
    private var stackedConstraints: [NSLayoutConstraint] = []
    private var sideBySideConstraints: [NSLayoutConstraint] = []
    private let outstandingLabel = UILabel()
    private let outstandingCaption = UILabel()
    private let statsRow = UIStackView()
    private let recentStack = UIStackView()
    private lazy var setupBanner = makeSetupBanner()
    private let mandateCard = MandateCardView()
    private var lastSnapshot: DashboardViewModel.Snapshot?
    private var isPremium = false

    init(viewModel: DashboardViewModel = DashboardViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        let compose = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            primaryAction: UIAction { [weak self] _ in self?.newInvoice() })
        compose.accessibilityLabel = String(localized: "New invoice")
        navigationItem.rightBarButtonItem = compose
        buildLayout()
        bind()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.load()
    }

    private func bind() {
        viewModel.snapshotPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.apply($0) }
            .store(in: &cancellables)
        AICreditsManager.store.$isPremium
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                self.isPremium = $0
                if let snapshot = self.lastSnapshot { self.applyMandate(snapshot) }
            }
            .store(in: &cancellables)
        mandateCard.onAction = { [weak self] in self?.perform($0) }
    }

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

        summaryColumn.axis = .vertical
        summaryColumn.spacing = DesignSystem.Spacing.l
        recentColumn.axis = .vertical
        recentColumn.spacing = DesignSystem.Spacing.l

        installColumns()

        setupBanner.isHidden = true
        summaryColumn.addArrangedSubview(setupBanner)
        summaryColumn.addArrangedSubview(makeOutstandingCard())
        statsRow.axis = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.spacing = DesignSystem.Spacing.m
        summaryColumn.addArrangedSubview(statsRow)
        mandateCard.isHidden = true
        summaryColumn.addArrangedSubview(mandateCard)

        let cta = DesignSystem.primaryButton(String(localized: "New Invoice"), symbol: "plus")
        cta.addAction(UIAction { [weak self] _ in self?.newInvoice() }, for: .touchUpInside)
        summaryColumn.addArrangedSubview(cta)

        let recentTitle = DesignSystem.label(String(localized: "Recent"), font: DesignSystem.Typography.title())
        recentColumn.addArrangedSubview(recentTitle)
        recentStack.axis = .vertical
        recentStack.spacing = DesignSystem.Spacing.s
        recentColumn.addArrangedSubview(recentStack)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        arrangeColumns()
    }

    /// Hosts the summary and the recent documents in one column that the layout
    /// below can switch between stacked and side by side.
    private func installColumns() {
        for column in [summaryColumn, recentColumn] {
            column.translatesAutoresizingMaskIntoConstraints = false
            columns.addSubview(column)
        }
        scrollView.embedColumn(columns, maxWidth: ColumnWidth.dashboard, insets: UIEdgeInsets(
            top: DesignSystem.Spacing.m, left: DesignSystem.Spacing.m,
            bottom: DesignSystem.Spacing.l, right: DesignSystem.Spacing.m))
        summaryWidth = summaryColumn.widthAnchor.constraint(equalToConstant: 0)
        columnGap = recentColumn.leadingAnchor.constraint(equalTo: summaryColumn.trailingAnchor, constant: DesignSystem.Spacing.l)
        NSLayoutConstraint.activate([
            summaryColumn.topAnchor.constraint(equalTo: columns.topAnchor),
            summaryColumn.leadingAnchor.constraint(equalTo: columns.leadingAnchor),
        ])
        stackedConstraints = [
            summaryColumn.trailingAnchor.constraint(equalTo: columns.trailingAnchor),
            recentColumn.topAnchor.constraint(equalTo: summaryColumn.bottomAnchor, constant: DesignSystem.Spacing.l),
            recentColumn.leadingAnchor.constraint(equalTo: columns.leadingAnchor),
            recentColumn.trailingAnchor.constraint(equalTo: columns.trailingAnchor),
            recentColumn.bottomAnchor.constraint(equalTo: columns.bottomAnchor),
        ]
        sideBySideConstraints = [
            summaryWidth,
            columnGap,
            recentColumn.topAnchor.constraint(equalTo: columns.topAnchor),
            recentColumn.trailingAnchor.constraint(equalTo: columns.trailingAnchor),
            columns.bottomAnchor.constraint(greaterThanOrEqualTo: summaryColumn.bottomAnchor),
            columns.bottomAnchor.constraint(greaterThanOrEqualTo: recentColumn.bottomAnchor),
        ]
        NSLayoutConstraint.activate(stackedConstraints)
    }

    /// Puts the summary and the recent documents side by side when the window is
    /// wide, with the gap between them on the fold when there is one, so nothing
    /// sits on the crease in book pose; stacks them in a narrow window.
    private func arrangeColumns() {
        let width = scrollView.bounds.width
        let isWide = width >= Self.sideBySideWidth
        if isWide != sideBySideConstraints.first?.isActive {
            if isWide {
                NSLayoutConstraint.deactivate(stackedConstraints)
                NSLayoutConstraint.activate(sideBySideConstraints)
            } else {
                NSLayoutConstraint.deactivate(sideBySideConstraints)
                NSLayoutConstraint.activate(stackedConstraints)
            }
        }
        guard isWide else { return }
        let inset = DesignSystem.Spacing.m
        let columnsWidth = min(ColumnWidth.dashboard, width - inset * 2)
        let columnsOrigin = (width - columnsWidth) / 2
        let minimumColumn: CGFloat = 240
        let gap = foldGap()
        let gapWidth = gap.map { $0.width < columnsWidth - minimumColumn * 2 ? $0.width : nil } ?? nil
        if let gap, let gapWidth {
            let foldStart = scrollView.convert(CGPoint(x: gap.minX, y: 0), from: view).x
            columnGap.constant = gapWidth
            summaryWidth.constant = min(max(minimumColumn, foldStart - columnsOrigin), columnsWidth - gapWidth - minimumColumn)
        } else {
            columnGap.constant = DesignSystem.Spacing.l
            summaryWidth.constant = (columnsWidth - DesignSystem.Spacing.l) / 2
        }
    }

    /// The fold's frame in this view's coordinates when the device has a
    /// vertical one that crosses this view, whether or not it is active.
    private func foldGap() -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        return view.reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.width > 0 && $0.height > $0.width }
    }

    private static let sideBySideWidth: CGFloat = 760

    private func makeOutstandingCard() -> UIView {
        let card = DesignSystem.card()
        outstandingCaption.text = String(localized: "Outstanding")
        outstandingCaption.font = DesignSystem.Typography.scaledSystem(13, .semibold, relativeTo: .footnote)
        outstandingCaption.textColor = DesignSystem.Color.secondary
        outstandingLabel.font = DesignSystem.Typography.mono(40, weight: .bold)
        outstandingLabel.textColor = DesignSystem.Color.label
        outstandingLabel.adjustsFontSizeToFitWidth = true
        outstandingLabel.minimumScaleFactor = 0.6
        let inner = UIStackView(arrangedSubviews: [outstandingCaption, outstandingLabel])
        inner.axis = .vertical
        inner.spacing = 6
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        inner.pinEdges(to: card, insets: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))
        return card
    }

    private func makeSetupBanner() -> UIView {
        let card = DesignSystem.card()
        card.backgroundColor = DesignSystem.Color.accent.withAlphaComponent(0.12)

        let icon = UIImageView(image: UIImage(systemName: "building.2.crop.circle.fill"))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 28)])

        let title = DesignSystem.label(String(localized: "Finish setting up your business"),
            font: DesignSystem.Typography.scaledSystem(15, .semibold, relativeTo: .subheadline))
        let subtitle = DesignSystem.label(String(localized: "Add your name, VAT ID, and IBAN so every invoice is complete."),
            font: DesignSystem.Typography.caption(), color: DesignSystem.Color.secondary)
        subtitle.numberOfLines = 0
        let textStack = UIStackView(arrangedSubviews: [title, subtitle])
        textStack.axis = .vertical
        textStack.spacing = 2

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = DesignSystem.Color.tertiary
        chevron.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [icon, textStack, chevron])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = DesignSystem.Spacing.m
        row.translatesAutoresizingMaskIntoConstraints = false
        row.isUserInteractionEnabled = false
        card.addSubview(row)
        row.pinEdges(to: card, insets: UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))

        card.isAccessibilityElement = true
        card.accessibilityTraits = .button
        card.accessibilityLabel = String(localized: "Finish setting up your business")
        card.accessibilityHint = String(localized: "Add your name, VAT ID, and IBAN")
        card.addGestureRecognizer(UITapGestureRecognizer(actionHandler: { [weak self] in
            Haptics.tap()
            self?.navigationController?.pushViewController(BusinessSettingsViewController(), animated: true)
        }))
        return card
    }

    private func apply(_ snapshot: DashboardViewModel.Snapshot) {
        lastSnapshot = snapshot
        setupBanner.isHidden = snapshot.sellerConfigured
        applyMandate(snapshot)
        outstandingLabel.text = Format.money(snapshot.outstanding)
        outstandingLabel.accessibilityLabel = String(localized: "Outstanding balance")
        outstandingLabel.accessibilityValue = Format.money(snapshot.outstanding)
        statsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statsRow.addArrangedSubview(statTile("\(snapshot.invoiceCount)", String(localized: "Invoices")))
        statsRow.addArrangedSubview(statTile("\(snapshot.estimateCount)", String(localized: "Estimates")))
        let overdueTap: (() -> Void)? = snapshot.overdueCount > 0 ? { [weak self] in
            Haptics.tap(); self?.tabBarController?.selectedIndex = 1
        } : nil
        statsRow.addArrangedSubview(statTile("\(snapshot.overdueCount)", String(localized: "Overdue"),
            tint: snapshot.overdueCount > 0 ? DesignSystem.Color.overdue : DesignSystem.Color.label,
            onTap: overdueTap))

        recentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if snapshot.recent.isEmpty {
            recentStack.addArrangedSubview(DesignSystem.emptyState(
                symbol: "tray", title: String(localized: "Nothing here yet"),
                subtitle: String(localized: "Your recent invoices and estimates will show up here.")))
        } else {
            for invoice in snapshot.recent {
                let row = InvoiceRowView(invoice: invoice,
                                         menu: { [weak self] in self?.recentMenu(for: invoice) },
                                         onTap: { [weak self] in self?.open(invoice) })
                recentStack.addArrangedSubview(row)
            }
        }
    }

    private func applyMandate(_ snapshot: DashboardViewModel.Snapshot) {
        guard let model = MandateCopy.card(countryCode: snapshot.sellerCountryCode, isPro: isPremium,
                                           peppolConfigured: snapshot.sellerPeppolConfigured) else {
            mandateCard.isHidden = true
            return
        }
        mandateCard.apply(model)
        mandateCard.isHidden = false
    }

    private func perform(_ action: MandateCardModel.Action) {
        switch action {
        case .unlockPro(let reason):
            present(UINavigationController(rootViewController: PaywallViewController(reason: reason)), animated: true)
        case .openPeppolSettings:
            navigationController?.pushViewController(BusinessSettingsViewController(focusesPeppol: true), animated: true)
        case .openBusinessSettings:
            navigationController?.pushViewController(BusinessSettingsViewController(), animated: true)
        case .informationOnly:
            break
        }
    }

    private func recentMenu(for invoice: Invoice) -> UIMenu {
        var children: [UIMenuElement] = [
            UIAction(title: String(localized: "Open"), image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.open(invoice) },
        ]
        if invoice.type == .invoice && invoice.status == .draft {
            children.append(UIAction(title: String(localized: "Mark Sent"), image: UIImage(systemName: "paperplane.fill")) { [weak self] _ in
                self?.markSent(invoice) })
        }
        if invoice.type == .invoice && invoice.status != .paid {
            children.append(UIAction(title: String(localized: "Mark Paid"), image: UIImage(systemName: "checkmark.circle.fill")) { [weak self] _ in
                self?.markPaid(invoice) })
        }
        if invoice.type == .estimate {
            children.append(UIAction(title: String(localized: "Convert to Invoice"), image: UIImage(systemName: "arrow.right.circle.fill")) { [weak self] _ in
                self?.convert(invoice) })
        }
        children.append(UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            self?.delete(invoice) })
        return UIMenu(children: children)
    }

    private func markSent(_ invoice: Invoice) {
        Haptics.success()
        Task {
            try? await InvoiceRepository.shared.markSent(id: invoice.id)
            viewModel.load()
        }
    }

    private func markPaid(_ invoice: Invoice) {
        Haptics.success()
        var paid = invoice
        paid.status = .paid
        Task {
            try? await InvoiceRepository.shared.save(paid)
            viewModel.load()
        }
    }

    private func convert(_ estimate: Invoice) {
        Task { [weak self] in
            let today = Format.today()
            guard let number = try? await BusinessRepository.shared.nextNumber(for: .invoice, on: today) else {
                self?.presentNumberAllocationFailure()
                return
            }
            Haptics.success()
            _ = try? await InvoiceRepository.shared.makeInvoice(fromEstimate: estimate, number: number, today: today)
            self?.viewModel.load()
        }
    }

    private func presentNumberAllocationFailure() {
        Haptics.warning()
        let alert = UIAlertController(
            title: String(localized: "Couldn't allocate a number"),
            message: String(localized: "Couldn't allocate a number — try again."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }

    private func delete(_ invoice: Invoice) {
        Haptics.warning()
        Task {
            try? await InvoiceRepository.shared.delete(id: invoice.id)
            viewModel.load()
        }
    }

    private func statTile(_ value: String, _ caption: String, tint: UIColor = DesignSystem.Color.label,
                          onTap: (() -> Void)? = nil) -> UIView {
        let card = DesignSystem.card()
        let valueLabel = DesignSystem.label(value, font: DesignSystem.Typography.mono(26, weight: .bold), color: tint)
        let captionLabel = DesignSystem.label(caption, font: DesignSystem.Typography.caption(), color: DesignSystem.Color.secondary)
        let inner = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        inner.axis = .vertical
        inner.spacing = 2
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.isUserInteractionEnabled = false
        card.addSubview(inner)
        inner.pinEdges(to: card, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        card.isAccessibilityElement = true
        card.accessibilityLabel = caption
        card.accessibilityValue = value
        if let onTap {
            card.accessibilityTraits = .button
            card.accessibilityHint = String(localized: "Shows overdue invoices")
            let tap = UITapGestureRecognizer(actionHandler: onTap)
            card.addGestureRecognizer(tap)
        }
        return card
    }

    private func newInvoice() {
        BusinessSetupGate.beforeNewDocument(from: self) { [weak self] in
            let editor = InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(kind: .invoice))
            self?.navigationController?.pushViewController(editor, animated: true)
        }
    }

    private func open(_ invoice: Invoice) {
        let editor = InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(existing: invoice))
        navigationController?.pushViewController(editor, animated: true)
    }
}

import Combine
import UIKit
import PayDayKit

/// The home screen: outstanding receivables headline, quick actions, and a few
/// recent documents. Binds to its view model via the `PassthroughSubject` seam.
final class DashboardViewController: UIViewController {
    private let viewModel: DashboardViewModel
    private var cancellables = Set<AnyCancellable>()

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let outstandingLabel = UILabel()
    private let outstandingCaption = UILabel()
    private let statsRow = UIStackView()
    private let recentStack = UIStackView()
    private lazy var setupBanner = makeSetupBanner()

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
        compose.accessibilityLabel = "New invoice"
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
    }

    private func buildLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.pinEdges(to: view)

        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.l
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: DesignSystem.Spacing.m),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: DesignSystem.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -DesignSystem.Spacing.m),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -DesignSystem.Spacing.l),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -DesignSystem.Spacing.m * 2),
        ])

        setupBanner.isHidden = true
        stack.addArrangedSubview(setupBanner)
        stack.addArrangedSubview(makeOutstandingCard())
        statsRow.axis = .horizontal
        statsRow.distribution = .fillEqually
        statsRow.spacing = DesignSystem.Spacing.m
        stack.addArrangedSubview(statsRow)

        let cta = DesignSystem.primaryButton("New Invoice", symbol: "plus")
        cta.addAction(UIAction { [weak self] _ in self?.newInvoice() }, for: .touchUpInside)
        stack.addArrangedSubview(cta)

        let recentTitle = DesignSystem.label("Recent", font: DesignSystem.Typography.title())
        stack.addArrangedSubview(recentTitle)
        recentStack.axis = .vertical
        recentStack.spacing = DesignSystem.Spacing.s
        stack.addArrangedSubview(recentStack)
    }

    private func makeOutstandingCard() -> UIView {
        let card = DesignSystem.card()
        outstandingCaption.text = "Outstanding"
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

        let title = DesignSystem.label("Finish setting up your business",
            font: DesignSystem.Typography.scaledSystem(15, .semibold, relativeTo: .subheadline))
        let subtitle = DesignSystem.label("Add your name, VAT ID, and IBAN so every invoice is complete.",
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
        card.accessibilityLabel = "Finish setting up your business"
        card.accessibilityHint = "Add your name, VAT ID, and IBAN"
        card.addGestureRecognizer(UITapGestureRecognizer(actionHandler: { [weak self] in
            Haptics.tap()
            self?.navigationController?.pushViewController(BusinessSettingsViewController(), animated: true)
        }))
        return card
    }

    private func apply(_ snapshot: DashboardViewModel.Snapshot) {
        setupBanner.isHidden = snapshot.sellerConfigured
        outstandingLabel.text = Format.money(snapshot.outstanding)
        outstandingLabel.accessibilityLabel = "Outstanding balance"
        outstandingLabel.accessibilityValue = Format.money(snapshot.outstanding)
        statsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statsRow.addArrangedSubview(statTile("\(snapshot.invoiceCount)", "Invoices"))
        statsRow.addArrangedSubview(statTile("\(snapshot.estimateCount)", "Estimates"))
        let overdueTap: (() -> Void)? = snapshot.overdueCount > 0 ? { [weak self] in
            Haptics.tap(); self?.tabBarController?.selectedIndex = 1
        } : nil
        statsRow.addArrangedSubview(statTile("\(snapshot.overdueCount)", "Overdue",
            tint: snapshot.overdueCount > 0 ? DesignSystem.Color.overdue : DesignSystem.Color.label,
            onTap: overdueTap))

        recentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if snapshot.recent.isEmpty {
            recentStack.addArrangedSubview(DesignSystem.emptyState(
                symbol: "tray", title: "Nothing here yet",
                subtitle: "Your recent invoices and estimates will show up here."))
        } else {
            for invoice in snapshot.recent {
                let row = InvoiceRowView(invoice: invoice,
                                         menu: { [weak self] in self?.recentMenu(for: invoice) },
                                         onTap: { [weak self] in self?.open(invoice) })
                recentStack.addArrangedSubview(row)
            }
        }
    }

    private func recentMenu(for invoice: Invoice) -> UIMenu {
        var children: [UIMenuElement] = [
            UIAction(title: "Open", image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.open(invoice) },
        ]
        if invoice.type == .invoice && invoice.status == .draft {
            children.append(UIAction(title: "Mark Sent", image: UIImage(systemName: "paperplane.fill")) { [weak self] _ in
                self?.markSent(invoice) })
        }
        if invoice.type == .invoice && invoice.status != .paid {
            children.append(UIAction(title: "Mark Paid", image: UIImage(systemName: "checkmark.circle.fill")) { [weak self] _ in
                self?.markPaid(invoice) })
        }
        if invoice.type == .estimate {
            children.append(UIAction(title: "Convert to Invoice", image: UIImage(systemName: "arrow.right.circle.fill")) { [weak self] _ in
                self?.convert(invoice) })
        }
        children.append(UIAction(title: "Delete", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
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
            title: "Couldn't allocate a number",
            message: "Couldn't allocate a number — try again.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
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
            card.accessibilityHint = "Shows overdue invoices"
            let tap = UITapGestureRecognizer(actionHandler: onTap)
            card.addGestureRecognizer(tap)
        }
        return card
    }

    private func newInvoice() {
        let editor = InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(kind: .invoice))
        navigationController?.pushViewController(editor, animated: true)
    }

    private func open(_ invoice: Invoice) {
        let editor = InvoiceEditorViewController(viewModel: InvoiceEditorViewModel(existing: invoice))
        navigationController?.pushViewController(editor, animated: true)
    }
}

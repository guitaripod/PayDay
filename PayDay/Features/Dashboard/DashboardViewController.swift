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

    init(viewModel: DashboardViewModel = DashboardViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = DesignSystem.Color.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.pencil"),
            primaryAction: UIAction { [weak self] _ in self?.newInvoice() })
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
        view.addSubview(scrollView)
        scrollView.pinEdges(toSafeAreaOf: view)

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
        outstandingCaption.font = .systemFont(ofSize: 13, weight: .semibold)
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

    private func apply(_ snapshot: DashboardViewModel.Snapshot) {
        outstandingLabel.text = Format.money(snapshot.outstanding)
        statsRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        statsRow.addArrangedSubview(statTile("\(snapshot.invoiceCount)", "Invoices"))
        statsRow.addArrangedSubview(statTile("\(snapshot.estimateCount)", "Estimates"))
        statsRow.addArrangedSubview(statTile("\(snapshot.overdueCount)", "Overdue", tint: DesignSystem.Color.overdue))

        recentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if snapshot.recent.isEmpty {
            recentStack.addArrangedSubview(DesignSystem.label("No documents yet. Create your first invoice.",
                font: DesignSystem.Typography.body(), color: DesignSystem.Color.secondary))
        } else {
            for invoice in snapshot.recent {
                recentStack.addArrangedSubview(InvoiceRowView(invoice: invoice) { [weak self] in self?.open(invoice) })
            }
        }
    }

    private func statTile(_ value: String, _ caption: String, tint: UIColor = DesignSystem.Color.label) -> UIView {
        let card = DesignSystem.card()
        let valueLabel = DesignSystem.label(value, font: DesignSystem.Typography.mono(26, weight: .bold), color: tint)
        let captionLabel = DesignSystem.label(caption, font: DesignSystem.Typography.caption(), color: DesignSystem.Color.secondary)
        let inner = UIStackView(arrangedSubviews: [valueLabel, captionLabel])
        inner.axis = .vertical
        inner.spacing = 2
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        inner.pinEdges(to: card, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
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

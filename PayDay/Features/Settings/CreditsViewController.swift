import Combine
import UIKit

/// Shows the user's credit balance and what credits are for. Topping up is an
/// explicit button, never an automatic redirect to the paywall (Settings should
/// inform, not sell).
final class CreditsViewController: UIViewController {
    private let store = AICreditsManager.store
    private var cancellables = Set<AnyCancellable>()
    private let balanceLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Credits"
        view.backgroundColor = DesignSystem.Color.background
        build()
        store.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.balanceLabel.text = "\($0)" }
            .store(in: &cancellables)
        Task { await store.refresh() }
    }

    private func build() {
        let card = DesignSystem.card()
        let caption = DesignSystem.label("Balance", font: DesignSystem.Typography.headline(), color: DesignSystem.Color.secondary)
        balanceLabel.font = DesignSystem.Typography.mono(48, weight: .bold)
        balanceLabel.textColor = DesignSystem.Color.label
        balanceLabel.text = "\(store.balance)"
        balanceLabel.adjustsFontForContentSizeCategory = true
        balanceLabel.accessibilityLabel = "Credit balance"
        let creditsCaption = DesignSystem.label("credits", font: DesignSystem.Typography.body(), color: DesignSystem.Color.tertiary)
        let inner = UIStackView(arrangedSubviews: [caption, balanceLabel, creditsCaption])
        inner.axis = .vertical
        inner.spacing = 2
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        inner.pinEdges(to: card, insets: UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20))

        let explainer = DesignSystem.label(
            "Credits cover each invoice you send over the Peppol network and optional AI actions — drafting line items from a photo or text, and writing payment reminders. The app is fully usable without them.",
            font: DesignSystem.Typography.body(), color: DesignSystem.Color.secondary)

        let topUp = DesignSystem.primaryButton("Top up credits", symbol: "bolt.fill")
        topUp.addAction(UIAction { [weak self] _ in
            let paywall = PaywallViewController(reason: "Top up credits for Peppol sends and AI drafting.")
            self?.present(UINavigationController(rootViewController: paywall), animated: true)
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [card, explainer, topUp])
        stack.axis = .vertical
        stack.spacing = DesignSystem.Spacing.l
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: DesignSystem.Spacing.l),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: DesignSystem.Spacing.m),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -DesignSystem.Spacing.m),
        ])
    }
}

import UIKit

/// The dashboard's country-aware e-invoicing card: status pill, plain-language
/// summary, the next dated deadline, and one action that moves the seller
/// toward compliance.
final class MandateCardView: UIView {
    var onAction: ((MandateCardModel.Action) -> Void)?

    private let titleLabel = DesignSystem.label(font: DesignSystem.Typography.scaledSystem(15, .semibold, relativeTo: .subheadline))
    private let bodyLabel = DesignSystem.label(font: DesignSystem.Typography.caption(), color: DesignSystem.Color.secondary)
    private let deadlineLabel = DesignSystem.label(font: DesignSystem.Typography.scaledSystem(12, .semibold, relativeTo: .caption1))
    private let actionButton = UIButton(type: .system)
    private let pillContainer = UIStackView()
    private var action: MandateCardModel.Action = .informationOnly

    init() {
        super.init(frame: .zero)
        backgroundColor = DesignSystem.Color.surface
        layer.cornerRadius = DesignSystem.Radius.card
        layer.cornerCurve = .continuous
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func apply(_ model: MandateCardModel) {
        titleLabel.text = model.title
        bodyLabel.text = model.body
        deadlineLabel.text = model.deadline
        deadlineLabel.isHidden = model.deadline == nil
        deadlineLabel.textColor = model.tone == .urgent ? DesignSystem.Color.overdue : DesignSystem.Color.accent
        pillContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        pillContainer.addArrangedSubview(DesignSystem.statusPill(Self.statusRaw(for: model.tone), title: model.pillTitle))
        action = model.action
        actionButton.isHidden = model.actionTitle == nil
        if let title = model.actionTitle {
            actionButton.configuration?.attributedTitle = AttributedString(
                title, attributes: AttributeContainer([.font: DesignSystem.Typography.scaledSystem(15, .semibold, relativeTo: .callout)]))
            actionButton.configuration?.image = UIImage(systemName: Self.symbol(for: model.action))
        }
        isAccessibilityElement = false
        accessibilityElements = [titleLabel, pillContainer, bodyLabel, deadlineLabel, actionButton].filter { !$0.isHidden }
    }

    private func build() {
        let icon = UIImageView(image: UIImage(systemName: "checkmark.seal.fill"))
        icon.tintColor = DesignSystem.Color.accent
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true

        titleLabel.numberOfLines = 0
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        pillContainer.axis = .horizontal
        pillContainer.alignment = .center
        pillContainer.setContentHuggingPriority(.required, for: .horizontal)
        pillContainer.setContentCompressionResistancePriority(.required, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [icon, titleLabel, pillContainer])
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = DesignSystem.Spacing.s
        header.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (header: UIStackView, _) in
            header.axis = header.traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
            header.alignment = header.axis == .vertical ? .leading : .center
        }

        bodyLabel.numberOfLines = 0
        deadlineLabel.numberOfLines = 0

        var config = UIButton.Configuration.plain()
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.contentInsets = .zero
        config.baseForegroundColor = DesignSystem.Color.accent
        actionButton.configuration = config
        actionButton.contentHorizontalAlignment = .leading
        actionButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            Haptics.tap()
            self.onAction?(self.action)
        }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [header, bodyLabel, deadlineLabel, actionButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = DesignSystem.Spacing.s
        stack.setCustomSpacing(4, after: bodyLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        stack.pinEdges(to: self, insets: UIEdgeInsets(top: 16, left: 16, bottom: 12, right: 16))
    }

    private static func statusRaw(for tone: MandateCardModel.Tone) -> String {
        switch tone {
        case .urgent: return "overdue"
        case .active: return "sent"
        case .upcoming: return "viewed"
        case .neutral: return "draft"
        }
    }

    private static func symbol(for action: MandateCardModel.Action) -> String {
        switch action {
        case .unlockPro: return "lock.open.fill"
        case .openPeppolSettings, .openBusinessSettings: return "chevron.right"
        case .informationOnly: return "chevron.right"
        }
    }
}

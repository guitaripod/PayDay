import UIKit

/// A list column beside a detail column, for the tabs whose screens are a list
/// that opens a document, a client or a settings form. Wide windows (the inner
/// iPhone Duo display, a landscape phone) show both columns; narrow ones fold
/// onto the list and push the detail, so the phone flow is unchanged.
///
/// Detail screens always live in the secondary column's navigation stack, so
/// folding the device closed and open again moves the person between the two
/// layouts without losing what they were looking at.
final class ListDetailSplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    private let listNavigation: UINavigationController
    private let detailNavigation = UINavigationController()
    private let placeholderSymbol: String
    private(set) var showsPlaceholder = true
    private var detailIsAutomatic = false

    init(list: UIViewController, placeholderSymbol: String) {
        self.listNavigation = UINavigationController(rootViewController: list)
        self.listNavigation.navigationBar.prefersLargeTitles = true
        self.placeholderSymbol = placeholderSymbol
        super.init(style: .doubleColumn)
        delegate = self
        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        setViewController(listNavigation, for: .primary)
        setViewController(detailNavigation, for: .secondary)
        showPlaceholder()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let isNarrow = view.bounds.width < Self.twoColumnMinimumWidth
        guard isNarrow != foldsOntoList else { return }
        foldsOntoList = isNarrow
        if isNarrow {
            traitOverrides.horizontalSizeClass = .compact
        } else {
            traitOverrides.remove(UITraitHorizontalSizeClass.self)
        }
    }

    /// A tall inner display is too narrow for a list beside a document: tiling
    /// would squeeze the list, and the system's alternative hides it behind a
    /// button over an empty page. Such a window gets the phone flow instead, a
    /// list that pushes the document, which is also what the outer display shows.
    private static let twoColumnMinimumWidth: CGFloat = 800
    private var foldsOntoList = false

    /// The list screen at the root of the primary column.
    var primaryList: UIViewController? { listNavigation.viewControllers.first }

    /// Whether a detail column sits beside the list right now.
    var isShowingBothColumns: Bool { !isCollapsed }

    /// Replaces the detail column's stack with `stack` and brings it forward
    /// when the window only has room for one column. `isAutomatic` marks a detail
    /// opened only to fill the empty column, which a narrow window drops in
    /// favour of the list.
    func showDetail(_ stack: [UIViewController], isAutomatic: Bool = false) {
        guard !stack.isEmpty else { return showPlaceholder() }
        showsPlaceholder = false
        detailIsAutomatic = isAutomatic
        detailNavigation.setViewControllers(stack, animated: false)
        if isCollapsed { show(.secondary) }
    }

    /// Returns the detail column to its empty state, and the list to the front.
    func clearDetail() {
        guard !showsPlaceholder else { return }
        showPlaceholder()
        if isCollapsed { show(.primary) }
    }

    private func showPlaceholder() {
        showsPlaceholder = true
        detailIsAutomatic = false
        detailNavigation.setViewControllers([makePlaceholder()], animated: false)
    }

    private func makePlaceholder() -> UIViewController {
        let placeholder = UIViewController()
        placeholder.view.backgroundColor = DesignSystem.Color.background
        var configuration = UIContentUnavailableConfiguration.empty()
        configuration.image = UIImage(systemName: placeholderSymbol)
        configuration.imageProperties.tintColor = DesignSystem.Color.tertiary
        configuration.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .light)
        placeholder.contentUnavailableConfiguration = configuration
        return placeholder
    }

    func splitViewController(
        _ svc: UISplitViewController,
        topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
    ) -> UISplitViewController.Column {
        showsPlaceholder || detailIsAutomatic ? .primary : .secondary
    }
}

extension UIViewController {
    /// The list-and-detail container this screen is a list in, when it is one.
    var listDetailSplit: ListDetailSplitViewController? {
        var candidate: UIViewController? = self
        while let current = candidate {
            if let split = current as? ListDetailSplitViewController { return split }
            candidate = current.parent
        }
        return nil
    }

    /// Opens `detail` in the detail column of the surrounding split, or pushes
    /// it when this screen is not in one.
    func showDetailScreen(_ detail: UIViewController, isAutomatic: Bool = false) {
        if let split = listDetailSplit {
            split.showDetail([detail], isAutomatic: isAutomatic)
        } else {
            navigationController?.pushViewController(detail, animated: true)
        }
    }
}

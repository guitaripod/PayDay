import UIKit

extension UITapGestureRecognizer {
    /// Convenience for wiring a tap to a closure without a target/action boilerplate
    /// or a stored selector. The closure is retained for the recognizer's lifetime.
    convenience init(actionHandler: @escaping () -> Void) {
        let target = ClosureTarget(actionHandler)
        self.init(target: target, action: #selector(ClosureTarget.invoke))
        objc_setAssociatedObject(self, &ClosureTarget.key, target, .OBJC_ASSOCIATION_RETAIN)
    }
}

private final class ClosureTarget: NSObject {
    nonisolated(unsafe) static var key = 0
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke() { handler() }
}

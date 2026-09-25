import Foundation

/// Whether now is a good moment to trigger the App Store rating prompt, as a
/// pure function of what's happened so far. Kept free of StoreKit/UIKit so
/// the timing math is exhaustively testable without a device or simulator.
///
/// Delivering a compliant invoice — a completed share sheet or an accepted
/// Peppol transmission — is Pay Day's core value moment: rare per session and
/// heavy (it commits a legally binding document), so the first ask fires on
/// that first delivery rather than waiting for a second.
public enum ReviewEligibility {
    public static let firstAskThreshold = 1
    public static let minDaysBetweenAsks = 14
    public static let minNewSuccessesBetweenAsks = 3
    public static let maxAsksPerRollingYear = 3
    public static let rollingYear: TimeInterval = 365 * 24 * 60 * 60

    public static func shouldAsk(
        successCount: Int,
        askDates: [Date],
        successCountAtLastAsk: Int,
        now: Date
    ) -> Bool {
        let recentAskCount = askDates.lazy.filter { now.timeIntervalSince($0) < rollingYear }.count
        guard recentAskCount < maxAsksPerRollingYear else { return false }
        guard let lastAsk = askDates.max() else {
            return successCount >= firstAskThreshold
        }
        guard now.timeIntervalSince(lastAsk) >= Double(minDaysBetweenAsks) * 86_400 else { return false }
        return successCount - successCountAtLastAsk >= minNewSuccessesBetweenAsks
    }
}

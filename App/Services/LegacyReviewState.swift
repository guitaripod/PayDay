import Foundation
import MidgarCommerce

/// The ask history the app kept before `MidgarReviewPolicy`: a list of ask dates, and before that a "shown on this
/// version" flag. A person who was asked recently must not be asked again the day the policy changes, so the newest
/// ask becomes the policy's last prompt the first time it runs. A flag without a date is treated as an ask made at
/// the migration, which delays the next ask rather than permitting one early. The delivery tallies only fed the
/// retired eligibility rules, so they are removed.
nonisolated enum LegacyReviewState {
    static let askDatesKey = "payday.reviewAskDates"
    static let shownVersionKey = "payday.ratingPromptShownVersion"
    static let retiredKeys = [
        "payday.reviewSuccessCount", "payday.reviewSuccessCountAtLastAsk", "payday.reviewStateMigrated",
        "payday.deliveredDocumentCount",
    ]
    static let migratedKey = "payday.review.migratedToMidgar"

    static func migrate(from defaults: UserDefaults, into storage: any MidgarReviewStorage, now: Date = Date()) {
        guard !defaults.bool(forKey: migratedKey) else { return }
        defaults.set(true, forKey: migratedKey)
        let lastAsk = newestAsk(in: defaults, now: now)
        retire(in: defaults)
        guard let lastAsk else { return }
        var state = storage.load()
        guard state.lastPrompt == nil else { return }
        state.lastPrompt = lastAsk
        storage.save(state)
    }

    private static func newestAsk(in defaults: UserDefaults, now: Date) -> Date? {
        let dates = defaults.array(forKey: askDatesKey) as? [Date] ?? []
        let undated = defaults.string(forKey: shownVersionKey) != nil ? [now] : []
        return (dates + undated).max()
    }

    /// Removes the values only the retired mechanism read, once the policy holds what they said.
    private static func retire(in defaults: UserDefaults) {
        for key in [askDatesKey, shownVersionKey] + retiredKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

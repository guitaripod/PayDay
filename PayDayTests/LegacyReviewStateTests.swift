import Foundation
import MidgarCommerce
import Testing
@testable import PayDay

struct LegacyReviewStateTests {
    /// Holds one review state in memory. Reads and writes happen under one lock.
    private final class MemoryStorage: MidgarReviewStorage, @unchecked Sendable {
        private let lock = NSLock()
        private var state = MidgarReviewState()

        func load() -> MidgarReviewState {
            lock.lock()
            defer { lock.unlock() }
            return state
        }

        func save(_ state: MidgarReviewState) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            self.state = state
            return true
        }
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "payday.tests.review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func theNewestAskBecomesThePoliciesLastPromptAndTheOldKeysGo() {
        let defaults = freshDefaults()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_750_000_000)
        defaults.set([older, newer], forKey: LegacyReviewState.askDatesKey)
        defaults.set(4, forKey: "payday.reviewSuccessCount")
        let storage = MemoryStorage()

        LegacyReviewState.migrate(from: defaults, into: storage)

        #expect(storage.load().lastPrompt == newer)
        #expect(defaults.object(forKey: LegacyReviewState.askDatesKey) == nil)
        #expect(defaults.object(forKey: "payday.reviewSuccessCount") == nil)
    }

    @Test func aShownVersionFlagWithoutADateCountsAsAskedNow() {
        let defaults = freshDefaults()
        defaults.set("1.0.0", forKey: LegacyReviewState.shownVersionKey)
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let storage = MemoryStorage()

        LegacyReviewState.migrate(from: defaults, into: storage, now: now)

        #expect(storage.load().lastPrompt == now)
        #expect(defaults.object(forKey: LegacyReviewState.shownVersionKey) == nil)
    }

    @Test func aPersonNeverAskedStaysUnasked() {
        let storage = MemoryStorage()

        LegacyReviewState.migrate(from: freshDefaults(), into: storage)

        #expect(storage.load().lastPrompt == nil)
    }

    @Test func theMigrationRunsOnce() {
        let defaults = freshDefaults()
        let storage = MemoryStorage()
        LegacyReviewState.migrate(from: defaults, into: storage)
        defaults.set([Date(timeIntervalSince1970: 1_700_000_000)], forKey: LegacyReviewState.askDatesKey)

        LegacyReviewState.migrate(from: defaults, into: storage)

        #expect(storage.load().lastPrompt == nil)
    }

    @Test func aNewerPolicyStateIsNotOverwritten() {
        let defaults = freshDefaults()
        defaults.set([Date(timeIntervalSince1970: 1_700_000_000)], forKey: LegacyReviewState.askDatesKey)
        let storage = MemoryStorage()
        let recent = Date(timeIntervalSince1970: 1_760_000_000)
        storage.save(MidgarReviewState(lastPrompt: recent))

        LegacyReviewState.migrate(from: defaults, into: storage)

        #expect(storage.load().lastPrompt == recent)
    }
}

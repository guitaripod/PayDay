import Foundation

/// Raw values align with `UIUserInterfaceStyle` so a stored mode maps straight
/// onto a window override.
enum AppearanceMode: Int, CaseIterable {
    case system = 0
    case light = 1
    case dark = 2
}

enum AppSettings {
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let appearance = "payday.appearance"
        static let hasOnboarded = "payday.hasOnboarded"
        static let didSeedDemo = "payday.didSeedDemo"
        static let defaultCurrency = "payday.defaultCurrency"
        static let defaultVATRate = "payday.defaultVATRate"
        static let defaultPaymentTermDays = "payday.defaultPaymentTermDays"
        static let defaultEInvoiceProfile = "payday.defaultEInvoiceProfile"
        static let aiConsentGranted = "payday.aiConsentGranted"
        static let aiConsentProvider = "payday.aiConsentProvider"
        static let reviewSuccessCount = "payday.reviewSuccessCount"
        static let reviewAskDates = "payday.reviewAskDates"
        static let reviewSuccessCountAtLastAsk = "payday.reviewSuccessCountAtLastAsk"
        static let reviewStateMigrated = "payday.reviewStateMigrated"
        static let legacyRatingPromptShownVersion = "payday.ratingPromptShownVersion"
        static let legacyDeliveredDocumentCount = "payday.deliveredDocumentCount"
    }

    static var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.integer(forKey: Key.appearance)) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.appearance) }
    }

    static var hasOnboarded: Bool {
        get { defaults.bool(forKey: Key.hasOnboarded) }
        set { defaults.set(newValue, forKey: Key.hasOnboarded) }
    }

    static var didSeedDemo: Bool {
        get { defaults.bool(forKey: Key.didSeedDemo) }
        set { defaults.set(newValue, forKey: Key.didSeedDemo) }
    }

    static var defaultCurrencyCode: String {
        get { defaults.string(forKey: Key.defaultCurrency) ?? (Locale.current.currency?.identifier ?? "EUR") }
        set { defaults.set(newValue, forKey: Key.defaultCurrency) }
    }

    /// The seller's home standard VAT rate, used to pre-fill new lines.
    static var defaultVATRatePercent: Double {
        get { (defaults.object(forKey: Key.defaultVATRate) as? Double) ?? 24 }
        set { defaults.set(newValue, forKey: Key.defaultVATRate) }
    }

    static var defaultPaymentTermDays: Int {
        get { (defaults.object(forKey: Key.defaultPaymentTermDays) as? Int) ?? 14 }
        set { defaults.set(newValue, forKey: Key.defaultPaymentTermDays) }
    }

    static var defaultEInvoiceProfile: String {
        get { defaults.string(forKey: Key.defaultEInvoiceProfile) ?? "en16931" }
        set { defaults.set(newValue, forKey: Key.defaultEInvoiceProfile) }
    }

    /// Invoices the user has actually delivered — shared or transmitted over
    /// Peppol. Feeds `ReviewEligibility` as `successCount`.
    static var reviewSuccessCount: Int {
        get { defaults.integer(forKey: Key.reviewSuccessCount) }
        set { defaults.set(newValue, forKey: Key.reviewSuccessCount) }
    }

    /// Every past rating-prompt trigger, oldest first. Feeds `ReviewEligibility`
    /// as `askDates`; entries older than its rolling window are meaningless but
    /// harmless, since the window check re-derives from `now` on every call.
    static var reviewAskDates: [Date] {
        get { (defaults.array(forKey: Key.reviewAskDates) as? [Date]) ?? [] }
        set { defaults.set(newValue, forKey: Key.reviewAskDates) }
    }

    /// `reviewSuccessCount` at the moment of the most recent ask. Feeds
    /// `ReviewEligibility` as `successCountAtLastAsk`.
    static var reviewSuccessCountAtLastAsk: Int {
        get { defaults.integer(forKey: Key.reviewSuccessCountAtLastAsk) }
        set { defaults.set(newValue, forKey: Key.reviewSuccessCountAtLastAsk) }
    }

    /// One-time migration from the version-gated prompt this replaced. The
    /// delivery counter carries over unchanged; a prior "already shown this
    /// version" flag becomes one ask dated to the migration itself — the exact
    /// original date is unknown, so it's treated as having just happened
    /// (the conservative reading, since that delays the next ask rather than
    /// permitting one early) — so it still counts toward the rolling-year cap.
    /// The legacy keys are never read again after this runs.
    static func migrateLegacyReviewStateIfNeeded() {
        guard !defaults.bool(forKey: Key.reviewStateMigrated) else { return }
        defaults.set(true, forKey: Key.reviewStateMigrated)
        let legacyCount = defaults.integer(forKey: Key.legacyDeliveredDocumentCount)
        if legacyCount > 0 {
            reviewSuccessCount = legacyCount
        }
        if defaults.string(forKey: Key.legacyRatingPromptShownVersion) != nil {
            reviewAskDates = [Date()]
            reviewSuccessCountAtLastAsk = legacyCount
        }
        defaults.removeObject(forKey: Key.legacyRatingPromptShownVersion)
        defaults.removeObject(forKey: Key.legacyDeliveredDocumentCount)
    }

    /// Whether the user has explicitly consented to Pay Day sending AI-drafting
    /// content to its third-party AI provider. Gates every AI call.
    static var aiConsentGranted: Bool {
        get { defaults.bool(forKey: Key.aiConsentGranted) && defaults.string(forKey: Key.aiConsentProvider) == aiProvider }
        set {
            defaults.set(newValue, forKey: Key.aiConsentGranted)
            defaults.set(aiProvider, forKey: Key.aiConsentProvider)
        }
    }

    private static let aiProvider = "anthropic"
}

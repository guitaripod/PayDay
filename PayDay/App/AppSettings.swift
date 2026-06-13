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
        static let ratingPromptShownVersion = "payday.ratingPromptShownVersion"
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

    static var ratingPromptShownVersion: String? {
        get { defaults.string(forKey: Key.ratingPromptShownVersion) }
        set { defaults.set(newValue, forKey: Key.ratingPromptShownVersion) }
    }
}

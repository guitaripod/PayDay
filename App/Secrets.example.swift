import Foundation

/// Copy to `Secrets.swift` (gitignored) via `scripts/setup.sh`, then fill in.
/// `Secrets.swift` is excluded from the build when absent and injected by CI.
/// Service addresses are not secrets: mako and Pay Day's worker are reached through the Midgar gateway,
/// whose address lives in `PayDayMidgar`.
enum Secrets {
    /// RevenueCat public SDK key for the `payday` app.
    static let revenueCatPublicKey = "appl_XXXXXXXXXXXXXXXXXXXXXXXXXX"
}

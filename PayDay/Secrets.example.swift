import Foundation

/// Copy to `Secrets.swift` (gitignored) via `scripts/setup.sh`, then fill in.
/// `Secrets.swift` is excluded from the build when absent and injected by CI.
enum Secrets {
    /// Pay Day's own Cloudflare Worker (VIES VAT validation, ECB FX, Peppol broker).
    static let workerBaseURL = URL(string: "https://payday-worker.guitaripod.workers.dev")!

    /// Shared AI-credits backend (identity, credits ledger, RevenueCat, AI run).
    static let makoBaseURL = URL(string: "https://mako.midgarcorp.cc")!

    /// RevenueCat public SDK key for the `payday` app.
    static let revenueCatPublicKey = "appl_XXXXXXXXXXXXXXXXXXXXXXXXXX"

    /// Sign in with Apple redirect URI (web auth flow), if used.
    static let redirectURI = "https://mako.midgarcorp.cc/auth/callback"
}

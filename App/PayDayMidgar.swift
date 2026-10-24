import Foundation
import MidgarCommerce
import MidgarCore
import MidgarCredits
import MidgarPortal

/// The composition root of everything Pay Day shares with the other Midgar apps: the Midgar ID, the gateway client
/// built on it, the purchase engine and the credit wallet, the client of Pay Day's own worker and the gateway addresses
/// of mako and the worker. One instance lives for the whole process, so there is one identity and one
/// `Transaction.updates` listener.
final class PayDayMidgar: Sendable {
    /// The registry slug: the `X-App-ID` of every gateway call.
    static let appID = "pay-day"

    /// The tenant mako and the worker resolve the app to. It is the id AICredits and the worker have always sent, so
    /// every existing credit balance and Peppol send record keeps its owner.
    static let tenantID = "payday"

    /// The bundle id the registry holds for the App Store record.
    static let bundleID = "com.guitaripod.payday"

    /// The log file name, kept from the retired per-app logger so the `ios-device-logs` workflow still finds it.
    static let logFileName = "payday.log"

    /// mako behind the gateway: `/v1/intelligence/` is stripped and the rest reaches mako's own routes, so
    /// `<this>/v1/credits/balance` is mako's `/v1/credits/balance`.
    static let intelligenceURL = MidgarHTTPConfiguration.defaultBaseURL.appendingPathComponent("v1/intelligence")

    /// The longest a call waits for the Midgar ID's access token before it goes without.
    static let tokenWait: Duration = .seconds(2)

    /// How long an advisory call to the worker (VIES, FX, Peppol lookup) or the Peppol send waits before it gives up.
    static let workerTimeout: TimeInterval = 12

    static let shared = PayDayMidgar()

    /// The Midgar ID client. Minted on first launch, attached on every later one, shared through the keychain group.
    let identity: MidgarIdentity

    /// The gateway client that carries the Midgar ID's bearer token, for the portal's "Your Midgar".
    let account: MidgarHTTPClient

    /// The gateway client for mako and Pay Day's worker, which keep the mako api key in `Authorization`.
    let gateway: PayDayGateway

    /// The purchase engine for the Pro plans and the credit packs: StoreKit 2 with the Midgar ID as `appAccountToken`.
    /// Nil in a test host or a demo capture, which must not reach the ledger.
    let store: MidgarStore?

    /// The wallet behind the credit packs: the balance, the purchase and the credit on the Midgar ID, with the old
    /// AICredits api key as the legacy key so the balance from before the move stays linked. Nil where `store` is.
    let credits: MidgarCredits?

    private init() {
        let configuration = MidgarHTTPConfiguration(appID: Self.appID)
        let identity = MidgarIdentity(httpConfiguration: configuration, bundleID: Self.bundleID)
        self.identity = identity
        let account = MidgarHTTPClient(configuration: identity.authorizing(configuration))
        self.account = account
        gateway = PayDayGateway(
            client: MidgarHTTPClient(
                configuration: MidgarHTTPConfiguration(
                    appID: Self.tenantID, timeout: Self.workerTimeout)))
        let commerce = Self.makeCommerce(identity: identity, account: account, configuration: configuration)
        store = commerce?.store
        credits = commerce?.credits
    }

    /// Builds the store and the wallet on it, or nothing where the app reaches no Midgar service. The wallet takes the
    /// plain configuration, because it authorizes its own requests: the legacy key and the Midgar token travel in
    /// different headers, and it sends the registry slug as `X-App-ID`, which mako accepts next to its own tenant ids.
    private static func makeCommerce(
        identity: MidgarIdentity,
        account: MidgarHTTPClient,
        configuration: MidgarHTTPConfiguration
    ) -> (store: MidgarStore, credits: MidgarCredits)? {
        guard reachesMidgarServices else { return nil }
        let store = MidgarStore(configuration: PayDayPacks.storeConfiguration(), identity: identity, http: account)
        let credits = MidgarCredits(
            configuration: PayDayPacks.creditsConfiguration(),
            http: configuration,
            identity: identity,
            purchasing: store,
            legacyAPIKey: { await AICreditsManager.shared.legacyAPIKey() }
        )
        return (store, credits)
    }

    /// The `X-Midgar-Token` header for a call to mako, which is how mako links the legacy api key to the Midgar ID,
    /// or nothing when the identity cannot answer within `tokenWait` or the host reaches no Midgar service. A call
    /// never waits on or fails for the token.
    func midgarTokenHeaders() async -> [String: String] {
        guard Self.reachesMidgarServices else { return [:] }
        return await identity.midgarTokenHeader(within: Self.tokenWait).map { [$0.name: $0.value] } ?? [:]
    }

    /// The portal configuration of Settings: the authorized client, so "Your Midgar" shows what the person owns in
    /// the other apps and a cross-sell skips an app they already use.
    var portalConfig: MidgarPortal.MidgarConfig {
        MidgarPortal.MidgarConfig(placement: "settings", account: Self.reachesMidgarServices ? account : nil)
    }

    /// Opens the log file. Call first thing at launch so nothing before the rest of the setup is lost.
    static func configureLogging() {
        MidgarLog.configure(fileName: logFileName)
        removeRetiredLogArchive()
    }

    /// Deletes `payday.previous.log`, the archive the retired per-app logger left. MidgarLog rotates into numbered
    /// archives, so nothing writes or reads the old name any more.
    private static func removeRetiredLogArchive() {
        guard let library = try? FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        else { return }
        try? FileManager.default.removeItem(
            at: library.appendingPathComponent("Logs/payday.previous.log"))
    }

    /// Configures anonymous signals for the portal and starts the Midgar ID in the background, so the app holds one
    /// before mako is first asked to link it, and queues the Pro plans StoreKit already holds for the ledger (once per
    /// install), so a subscriber from before the move reaches their Midgar ID. Call once at launch. A test host or a demo
    /// capture talks to no Midgar service.
    func start() {
        guard Self.reachesMidgarServices else {
            MidgarLog.info("Midgar services not started: test host or demo", category: .auth)
            return
        }
        MidgarSignals.configure(configuration: MidgarHTTPConfiguration(appID: Self.appID))
        let identity = identity
        if let store {
            Task { await store.reportPurchaseHistory() }
        }
        Task {
            do {
                _ = try await identity.midgarId
                MidgarLog.info("Midgar ID ready", category: .auth)
            } catch {
                MidgarLog.info("Midgar ID not available yet: \(error)", category: .auth)
            }
        }
    }

    /// True only for the shipped app on a real launch: the Apple Ads install attribution is reported then and never from a
    /// debug build, a test host or a demo capture.
    static var isProductionLaunch: Bool {
        #if DEBUG
        false
        #else
        reachesMidgarServices
        #endif
    }

    /// False inside an XCTest or Swift Testing host and in a DEBUG demo capture, which must not mint identities or
    /// send anything to the production services.
    static var reachesMidgarServices: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return false }
        #if DEBUG
        if DemoWorld.isActive { return false }
        #endif
        return true
    }
}

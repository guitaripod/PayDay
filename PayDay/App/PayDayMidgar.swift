import Foundation
import MidgarCore
import MidgarPortal

/// The composition root of everything Pay Day shares with the other Midgar apps: the Midgar ID, the gateway client
/// built on it, the client of Pay Day's own worker and the gateway addresses of mako and the worker. One instance
/// lives for the whole process, so there is one identity.
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

    private init() {
        let configuration = MidgarHTTPConfiguration(appID: Self.appID)
        let identity = MidgarIdentity(httpConfiguration: configuration, bundleID: Self.bundleID)
        self.identity = identity
        account = MidgarHTTPClient(configuration: identity.authorizing(configuration))
        gateway = PayDayGateway(
            client: MidgarHTTPClient(
                configuration: MidgarHTTPConfiguration(
                    appID: Self.tenantID, timeout: Self.workerTimeout)))
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
    /// before mako is first asked to link it. Call once at launch. A test host or a demo capture talks to no Midgar
    /// service.
    func start() {
        guard Self.reachesMidgarServices else {
            MidgarLog.info("Midgar services not started: test host or demo", category: .auth)
            return
        }
        MidgarSignals.configure(configuration: MidgarHTTPConfiguration(appID: Self.appID))
        let identity = identity
        Task {
            do {
                _ = try await identity.midgarId
                MidgarLog.info("Midgar ID ready", category: .auth)
            } catch {
                MidgarLog.info("Midgar ID not available yet: \(error)", category: .auth)
            }
        }
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

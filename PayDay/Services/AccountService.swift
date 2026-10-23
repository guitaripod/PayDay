import Foundation
import MidgarCore

/// Deletes the user's account end to end (App Store 5.1.1(v)): the worker's Peppol transmission records first, then
/// the server-side mako identity + credit ledger, the local AICredits identity, and all on-device business data.
/// The worker step has to run before mako, because the worker authenticates with the mako api key.
enum AccountService {
    enum AccountError: LocalizedError {
        case offline
        case serverError(Int)
        var errorDescription: String? {
            switch self {
            case .offline: return String(localized: "You need a connection to delete your account — try again when online.")
            case .serverError(let code): return String(localized: "The server couldn't delete the account (\(code)). Try again.",
                                                       comment: "Account deletion failure with the numeric HTTP status code")
            }
        }
    }

    static func deleteAccount() async throws {
        if let apiKey = await AICreditsManager.shared.client.identity?.apiKey {
            try await deleteRemoteData(apiKey: apiKey)
        }
        await AICreditsManager.shared.client.signOut()
        try DatabaseManager.shared.eraseAllData()
        AppSettings.didSeedDemo = false
        DemoSeeder.seedIfNeeded()
        MidgarLog.info("account deleted, local data erased, demo re-seeded", category: .credits)
    }

    /// Deletes the worker's records and then the mako identity. A worker failure throws before mako is touched, so the
    /// key that authenticates the worker call still works for the retry.
    static func deleteRemoteData(
        apiKey: String,
        gateway: PayDayGateway = PayDayMidgar.shared.gateway
    ) async throws {
        try await deleteWorkerData(apiKey: apiKey, gateway: gateway)
        try await deleteRemoteIdentity(apiKey: apiKey, gateway: gateway)
    }

    /// Deletes the worker's Peppol transmission records for the key's user through the gateway's worker route. The
    /// worker checks the key against mako, so this runs while the mako identity still exists. The endpoint is
    /// idempotent; the call is sent once.
    static func deleteWorkerData(
        apiKey: String,
        gateway: PayDayGateway = PayDayMidgar.shared.gateway
    ) async throws {
        do throws(MidgarHTTPError) {
            try await gateway.send(
                .delete, service: PayDayGateway.workerService, path: "v1/account", apiKey: apiKey, neverRetries: true)
        } catch {
            try acceptWorkerOrThrow(error)
        }
    }

    /// Deletes the mako identity behind the gateway. The call is sent once, because a repeat of an erasure could be
    /// mistaken for the first.
    static func deleteRemoteIdentity(
        apiKey: String,
        gateway: PayDayGateway = PayDayMidgar.shared.gateway
    ) async throws {
        do throws(MidgarHTTPError) {
            try await gateway.send(
                .delete, service: PayDayGateway.makoService, path: "v1/identity", apiKey: apiKey, neverRetries: true)
        } catch {
            try acceptOrThrow(error)
        }
    }

    /// mako answers 401 for a key it does not know, and deleting the account removes the user's keys with it, so after
    /// a deletion that finished server-side the retry arrives as 401; a 404 is the same verdict from the route layer.
    /// Both count as deleted. Any other status surfaces as a server error and a call that never got an answer as
    /// offline.
    private static func acceptOrThrow(_ error: MidgarHTTPError) throws {
        switch error {
        case .unauthorized, .notFound: return
        case .server(let status, _, _): throw AccountError.serverError(status)
        case .paymentRequired: throw AccountError.serverError(402)
        case .rateLimited: throw AccountError.serverError(429)
        default: throw AccountError.offline
        }
    }

    /// The worker step runs before mako's identity delete, so a 401 from the worker means a retry after the worker's
    /// records were already erased and mako's key is gone; that counts as deleted. A 404 is not accepted: a worker
    /// without the route would leave the records in place, so the deletion stops there. Any other status surfaces as a
    /// server error and a call that never got an answer as offline.
    private static func acceptWorkerOrThrow(_ error: MidgarHTTPError) throws {
        switch error {
        case .unauthorized: return
        case .notFound: throw AccountError.serverError(404)
        case .server(let status, _, _): throw AccountError.serverError(status)
        case .paymentRequired: throw AccountError.serverError(402)
        case .rateLimited: throw AccountError.serverError(429)
        default: throw AccountError.offline
        }
    }
}

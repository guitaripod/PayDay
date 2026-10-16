import Foundation

/// Deletes the user's account end to end (App Store 5.1.1(v)): the server-side
/// mako identity + credit ledger, the local AICredits identity, and all
/// on-device business data.
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

    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// Statuses that mean the identity no longer exists server-side. mako answers 401 for a key it does
    /// not know, and deleting the account removes the user's keys with it, so after a deletion that
    /// finished server-side the retry arrives as 401; a 404 is the same verdict from the route layer.
    private static let alreadyGoneStatuses: Set<Int> = [401, 404]

    static func deleteAccount() async throws {
        if let apiKey = await AICreditsManager.shared.client.identity?.apiKey {
            try await deleteRemoteIdentity(apiKey: apiKey)
        }
        await AICreditsManager.shared.client.signOut()
        try DatabaseManager.shared.eraseAllData()
        AppSettings.didSeedDemo = false
        DemoSeeder.seedIfNeeded()
        AppLogger.shared.info("account deleted, local data erased, demo re-seeded", category: .credits)
    }

    static func deleteRemoteIdentity(
        apiKey: String,
        baseURL: URL = Secrets.makoBaseURL,
        send: Send = { try await URLSession.shared.data(for: $0) }
    ) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/identity"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("payday", forHTTPHeaderField: "X-App-ID")
        let response: URLResponse
        do {
            (_, response) = try await send(request)
        } catch is URLError {
            throw AccountError.offline
        }
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode),
           !alreadyGoneStatuses.contains(http.statusCode) {
            throw AccountError.serverError(http.statusCode)
        }
    }
}

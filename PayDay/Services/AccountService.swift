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
            case .offline: return "You need a connection to delete your account — try again when online."
            case .serverError(let code): return "The server couldn't delete the account (\(code)). Try again."
            }
        }
    }

    static func deleteAccount() async throws {
        if let apiKey = await AICreditsManager.shared.client.identity?.apiKey {
            var request = URLRequest(url: Secrets.makoBaseURL.appendingPathComponent("v1/identity"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("payday", forHTTPHeaderField: "X-App-ID")
            let response: URLResponse
            do {
                (_, response) = try await URLSession.shared.data(for: request)
            } catch is URLError {
                throw AccountError.offline
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw AccountError.serverError(http.statusCode)
            }
        }
        await AICreditsManager.shared.client.signOut()
        try DatabaseManager.shared.eraseAllData()
        AppSettings.didSeedDemo = false
        DemoSeeder.seedIfNeeded()
        AppLogger.shared.info("account deleted, local data erased, demo re-seeded", category: .credits)
    }
}

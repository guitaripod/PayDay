import Foundation

/// Deletes the user's account end to end (App Store 5.1.1(v)): the server-side
/// mako identity + credit ledger, the local AICredits identity, and all
/// on-device business data.
enum AccountService {
    enum AccountError: LocalizedError {
        case serverError(Int)
        var errorDescription: String? {
            switch self {
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
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw AccountError.serverError(http.statusCode)
            }
        }
        await AICreditsManager.shared.client.signOut()
        try DatabaseManager.shared.eraseAllData()
        AppLogger.shared.info("account deleted and local data erased", category: .credits)
    }
}

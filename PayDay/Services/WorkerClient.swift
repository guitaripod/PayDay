import Foundation
import AICreditsCore

/// Authenticated HTTP to the Pay Day worker (VIES, FX, Peppol). Reuses the
/// AICredits identity's API key as the bearer — the worker shares the same
/// SIWA-linked identity for cross-device sync, so a separate auth flow is not
/// needed for these advisory services.
final class WorkerClient: Sendable {
    static let shared = WorkerClient()

    private let baseURL: URL
    private let session: URLSession
    private let identityProvider: @Sendable () async -> String?

    init(
        baseURL: URL = Secrets.workerBaseURL,
        session: URLSession = .shared,
        identityProvider: @escaping @Sendable () async -> String? = {
            await AICreditsManager.shared.client.identity?.apiKey
        }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.identityProvider = identityProvider
    }

    enum WorkerError: Error { case http(Int), decoding, offline }

    func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await send(path: path, method: "GET", body: nil, as: type)
    }

    func post<T: Decodable>(_ path: String, body: Encodable, as type: T.Type) async throws -> T {
        let data = try JSONEncoder().encode(AnyEncodable(body))
        return try await send(path: path, method: "POST", body: data, as: type)
    }

    private func send<T: Decodable>(path: String, method: String, body: Data?, as: T.Type) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = await identityProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WorkerError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw WorkerError.decoding }
        guard (200..<300).contains(http.statusCode) else { throw WorkerError.http(http.statusCode) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WorkerError.decoding
        }
    }
}

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeImpl = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeImpl(encoder) }
}

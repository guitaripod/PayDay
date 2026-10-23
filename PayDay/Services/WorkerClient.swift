import Foundation
import AICreditsCore
import MidgarCore

/// Authenticated HTTP to the Pay Day worker (VIES, FX, Peppol) through the Midgar gateway at `/v1/payday/`. Reuses
/// the AICredits identity's API key as the bearer, because the worker shares the same SIWA-linked identity for
/// cross-device sync, so a separate auth flow is not needed for these advisory services. Every call is sent once with
/// a short timeout: the calls are advisory and must degrade promptly when an upstream is unreachable, and the Peppol
/// send is never repeated by the transport.
final class WorkerClient: Sendable {
    static let shared = WorkerClient()

    private let gateway: PayDayGateway
    private let identityProvider: @Sendable () async -> String?

    init(
        gateway: PayDayGateway = PayDayMidgar.shared.gateway,
        identityProvider: @escaping @Sendable () async -> String? = {
            await AICreditsManager.shared.client.identity?.apiKey
        }
    ) {
        self.gateway = gateway
        self.identityProvider = identityProvider
    }

    enum WorkerError: Error { case http(Int, reason: String?), decoding, offline }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        try await send(.get, path: path, query: query, body: nil, as: type)
    }

    func post<T: Decodable>(_ path: String, body: any Encodable & Sendable, as type: T.Type) async throws -> T {
        try await send(.post, path: path, query: [], body: body, as: type)
    }

    private func send<T: Decodable>(
        _ method: MidgarHTTPMethod,
        path: String,
        query: [URLQueryItem],
        body: (any Encodable & Sendable)?,
        as: T.Type
    ) async throws -> T {
        let data: Data
        do throws(MidgarHTTPError) {
            data = try await gateway.send(
                method, service: PayDayGateway.workerService, path: path, query: query,
                apiKey: await identityProvider(), body: body, neverRetries: true)
        } catch {
            throw Self.workerError(for: error)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WorkerError.decoding
        }
    }

    /// The worker answers a failure with `{"error": "<reason>"}`, which the gateway client reports as the message of
    /// a server error, so the reason a Peppol send was refused reaches the alert as it always did. A status with no
    /// message of its own keeps the nil reason and falls back to the generic text.
    private static func workerError(for error: MidgarHTTPError) -> WorkerError {
        switch error {
        case .server(let status, _, let message):
            return .http(status, reason: message.hasPrefix("HTTP ") ? nil : message)
        case .unauthorized(let code):
            return .http(401, reason: code)
        case .paymentRequired(let code):
            return .http(402, reason: code)
        case .notFound(let code):
            return .http(404, reason: code)
        case .rateLimited(_, let code):
            return .http(429, reason: code)
        case .decoding:
            return .decoding
        default:
            return .offline
        }
    }
}

extension WorkerClient.WorkerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .offline:
            return String(localized: "Couldn't reach the network. Check your connection and try again.")
        case .decoding:
            return String(localized: "The server returned an unexpected response.")
        case let .http(status, reason):
            if let reason, !reason.isEmpty {
                return reason
            }
            return String(localized: "The server returned an error (\(status)).",
                          comment: "Generic HTTP failure with the numeric status code")
        }
    }
}

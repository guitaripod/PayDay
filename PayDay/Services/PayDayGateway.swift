import Foundation
import MidgarCore

/// The calls Pay Day makes to mako and to its own worker through the Midgar gateway: `/v1/intelligence/` for mako and
/// `/v1/payday/` for the worker. Both validate the caller by the mako api key in `Authorization`, which the gateway
/// forwards to these two services only, so every call carries the key AICredits holds.
nonisolated struct PayDayGateway: Sendable {
    static let workerService = "payday"
    static let makoService = "intelligence"

    private let client: MidgarHTTPClient

    init(client: MidgarHTTPClient) {
        self.client = client
    }

    /// Sends a call and returns the 2xx body. Throws the client's error for any other status. A call is sent once
    /// unless it is a GET and `neverRetries` is false, so the Peppol send and the account deletion are never repeated
    /// by the transport and a caller with its own retry loop keeps control of how often a POST repeats.
    @discardableResult
    func send(
        _ method: MidgarHTTPMethod,
        service: String,
        path: String,
        query: [URLQueryItem] = [],
        apiKey: String?,
        body: (any Encodable & Sendable)? = nil,
        neverRetries: Bool = false
    ) async throws(MidgarHTTPError) -> Data {
        var headers: [String: String] = [:]
        if let apiKey { headers["Authorization"] = "Bearer \(apiKey)" }
        let request = MidgarRequest(
            service: service, path: path, method: method, query: query,
            headers: headers, body: body, neverRetries: neverRetries)
        return try await client.sendRaw(request).0
    }
}

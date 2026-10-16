import Testing
import Foundation
@testable import PayDay

@Suite("Account deletion request")
struct AccountServiceTests {
    private let base = URL(string: "https://mako.example.test")!

    private func send(status: Int, recording requests: Requests = Requests()) -> AccountService.Send {
        { request in
            requests.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(), response)
        }
    }

    private final class Requests: @unchecked Sendable {
        private(set) var all: [URLRequest] = []
        func append(_ request: URLRequest) { all.append(request) }
    }

    @Test("A 404 means the identity is already gone and counts as deleted")
    func notFoundIsSuccess() async throws {
        try await AccountService.deleteRemoteIdentity(apiKey: "key", baseURL: base, send: send(status: 404))
    }

    @Test("A 401 after a finished deletion counts as deleted")
    func unauthorizedIsSuccess() async throws {
        try await AccountService.deleteRemoteIdentity(apiKey: "key", baseURL: base, send: send(status: 401))
    }

    @Test("A 200 deletes and sends the key for the payday tenant")
    func okSendsAuthorizedDelete() async throws {
        let requests = Requests()
        try await AccountService.deleteRemoteIdentity(apiKey: "secret", baseURL: base, send: send(status: 200, recording: requests))
        let request = try #require(requests.all.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/identity")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "X-App-ID") == "payday")
    }

    @Test("Other failures still surface the status code")
    func serverErrorThrows() async {
        do {
            try await AccountService.deleteRemoteIdentity(apiKey: "key", baseURL: base, send: send(status: 500))
            Issue.record("expected a server error")
        } catch let AccountService.AccountError.serverError(code) {
            #expect(code == 500)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("A network failure surfaces as offline")
    func offlineThrows() async {
        do {
            try await AccountService.deleteRemoteIdentity(apiKey: "key", baseURL: base, send: { _ in throw URLError(.notConnectedToInternet) })
            Issue.record("expected an offline error")
        } catch AccountService.AccountError.offline {
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

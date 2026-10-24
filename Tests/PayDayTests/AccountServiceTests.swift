import Foundation
import MidgarCore
import Testing
@testable import PayDay

@Suite("Account deletion request", .serialized)
struct AccountServiceTests {
    @Test("A 404 means the identity is already gone and counts as deleted")
    func notFoundIsSuccess() async throws {
        try await AccountService.deleteRemoteIdentity(apiKey: "key", gateway: GatewayStub.gateway(status: 404))
    }

    @Test("A 401 after a finished deletion counts as deleted")
    func unauthorizedIsSuccess() async throws {
        try await AccountService.deleteRemoteIdentity(apiKey: "key", gateway: GatewayStub.gateway(status: 401))
    }

    @Test("A 200 deletes through the gateway's mako route and sends the key for the payday tenant")
    func okSendsAuthorizedDelete() async throws {
        try await AccountService.deleteRemoteIdentity(apiKey: "secret", gateway: GatewayStub.gateway(status: 200))
        let request = try #require(GatewayStub.captured)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.midgarcorp.cc/v1/intelligence/v1/identity")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "X-App-ID") == "payday")
    }

    @Test("Other failures still surface the status code, and the deletion is sent once")
    func serverErrorThrowsAfterOneAttempt() async {
        do {
            try await AccountService.deleteRemoteIdentity(apiKey: "key", gateway: GatewayStub.gateway(status: 503))
            Issue.record("expected a server error")
        } catch let AccountService.AccountError.serverError(code) {
            #expect(code == 503)
            #expect(GatewayStub.requestCount == 1)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("The worker deletion goes to the payday route as DELETE with the key and the payday tenant")
    func workerDeleteSendsAuthorizedDelete() async throws {
        try await AccountService.deleteWorkerData(apiKey: "secret", gateway: GatewayStub.gateway(status: 204))
        let request = try #require(GatewayStub.captured)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.absoluteString == "https://api.midgarcorp.cc/v1/payday/v1/account")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "X-App-ID") == "payday")
    }

    @Test("A 204 from the worker counts as deleted")
    func workerNoContentIsSuccess() async throws {
        try await AccountService.deleteWorkerData(apiKey: "key", gateway: GatewayStub.gateway(status: 204))
    }

    @Test("A 401 from the worker counts as deleted, because mako's key is gone after a finished deletion")
    func workerUnauthorizedIsSuccess() async throws {
        try await AccountService.deleteWorkerData(apiKey: "key", gateway: GatewayStub.gateway(status: 401))
    }

    @Test("A 404 from the worker throws, because a worker without the route would keep the records")
    func workerNotFoundThrows() async {
        do {
            try await AccountService.deleteWorkerData(apiKey: "key", gateway: GatewayStub.gateway(status: 404))
            Issue.record("expected a server error")
        } catch let AccountService.AccountError.serverError(code) {
            #expect(code == 404)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("A 503 from the worker throws after exactly one attempt")
    func workerServerErrorThrowsAfterOneAttempt() async {
        do {
            try await AccountService.deleteWorkerData(apiKey: "key", gateway: GatewayStub.gateway(status: 503))
            Issue.record("expected a server error")
        } catch let AccountService.AccountError.serverError(code) {
            #expect(code == 503)
            #expect(GatewayStub.requestCount == 1)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("A worker failure throws before mako is called")
    func remoteDataStopsAtWorkerFailure() async {
        do {
            try await AccountService.deleteRemoteData(apiKey: "key", gateway: GatewayStub.gateway(status: 503))
            Issue.record("expected a server error")
        } catch let AccountService.AccountError.serverError(code) {
            #expect(code == 503)
            #expect(GatewayStub.requestCount == 1)
            #expect(GatewayStub.captured?.url?.absoluteString == "https://api.midgarcorp.cc/v1/payday/v1/account")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("A worker success is followed by the mako identity deletion")
    func remoteDataCallsWorkerThenMako() async throws {
        try await AccountService.deleteRemoteData(apiKey: "key", gateway: GatewayStub.gateway(status: 204))
        #expect(GatewayStub.requestCount == 2)
        #expect(GatewayStub.captured?.url?.absoluteString == "https://api.midgarcorp.cc/v1/intelligence/v1/identity")
    }

    @Test("A network failure surfaces as offline")
    func offlineThrows() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineStub.self]
        let gateway = PayDayGateway(
            client: MidgarHTTPClient(
                configuration: MidgarHTTPConfiguration(appID: "payday", session: URLSession(configuration: configuration))))
        do {
            try await AccountService.deleteRemoteIdentity(apiKey: "key", gateway: gateway)
            Issue.record("expected an offline error")
        } catch AccountService.AccountError.offline {
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    private final class OfflineStub: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
        override func stopLoading() {}
    }
}

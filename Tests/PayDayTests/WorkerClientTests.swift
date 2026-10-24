import Foundation
import Testing
@testable import PayDay

@Suite("Worker client behind the gateway", .serialized)
struct WorkerClientTests {
    private struct Reply: Decodable, Equatable { let rate: Double }
    private struct Payload: Encodable, Sendable { let vatID: String }

    private func client(status: Int, body: String = "{}") -> WorkerClient {
        WorkerClient(gateway: GatewayStub.gateway(status: status, body: body), identityProvider: { "key-123" })
    }

    @Test("A GET goes to the worker route behind the gateway with the key and the query")
    func getUsesTheGatewayRoute() async throws {
        let reply = try await client(status: 200, body: #"{"rate":1.25}"#).get(
            "v1/fx/rates",
            query: [URLQueryItem(name: "base", value: "EUR"), URLQueryItem(name: "quote", value: "USD")],
            as: Reply.self)
        #expect(reply == Reply(rate: 1.25))
        let request = try #require(GatewayStub.captured)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.midgarcorp.cc/v1/payday/v1/fx/rates?base=EUR&quote=USD")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key-123")
        #expect(request.value(forHTTPHeaderField: "X-App-ID") == "payday")
    }

    @Test("A POST carries its JSON body to the worker route")
    func postSendsTheBody() async throws {
        _ = try await client(status: 200, body: #"{"rate":1}"#).post("v1/vat/validate", body: Payload(vatID: "FI123"), as: Reply.self)
        let request = try #require(GatewayStub.captured)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.midgarcorp.cc/v1/payday/v1/vat/validate")
        #expect(GatewayStub.capturedBody.contains("FI123"))
    }

    @Test("The reason the worker gives for a refused Peppol send reaches the caller")
    func failureReasonSurvives() async {
        do {
            _ = try await client(status: 502, body: #"{"status":"failed","reason":"recipient_not_reachable","error":"recipient_not_reachable"}"#)
                .post("v1/peppol/send", body: Payload(vatID: "x"), as: Reply.self)
            Issue.record("expected a failure")
        } catch let WorkerClient.WorkerError.http(status, reason) {
            #expect(status == 502)
            #expect(reason == "recipient_not_reachable")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("A send is attempted once even when the gateway answers 503")
    func sendIsNotRepeated() async {
        _ = try? await client(status: 503, body: #"{"error":"peppol_not_configured"}"#)
            .post("v1/peppol/send", body: Payload(vatID: "x"), as: Reply.self)
        #expect(GatewayStub.requestCount == 1)
    }

    @Test("An advisory GET is attempted once even when the gateway answers 503")
    func advisoryGetIsNotRepeated() async {
        _ = try? await client(status: 503).get("v1/fx/rates", as: Reply.self)
        #expect(GatewayStub.requestCount == 1)
    }

    @Test("A status with no message of its own has no reason")
    func missingReasonIsNil() async {
        do {
            _ = try await client(status: 500, body: "").get("v1/fx/rates", as: Reply.self)
            Issue.record("expected a failure")
        } catch let WorkerClient.WorkerError.http(status, reason) {
            #expect(status == 500)
            #expect(reason == nil)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}

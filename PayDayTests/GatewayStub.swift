import Foundation
import MidgarCore
@testable import PayDay

/// Answers every request of a gateway client with a fixed status and body and records what was sent, so a test sees the
/// exact URL, headers and body a call put on the wire and how often it was sent.
final class GatewayStub: URLProtocol, @unchecked Sendable {
    /// Written only by the serialized suites before a request starts.
    nonisolated(unsafe) static var status = 200
    /// Written only by the serialized suites before a request starts.
    nonisolated(unsafe) static var responseBody = Data()
    /// Written by the loading thread, read by the test after the request finished.
    nonisolated(unsafe) static var captured: URLRequest?
    /// Counts the requests of the running test.
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.captured = request
        Self.requestCount += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A gateway whose client talks to the stub, with the app id the app uses for the worker and mako.
    static func gateway(status: Int, body: String = "") -> PayDayGateway {
        Self.status = status
        Self.responseBody = Data(body.utf8)
        Self.captured = nil
        Self.requestCount = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatewayStub.self]
        return PayDayGateway(
            client: MidgarHTTPClient(
                configuration: MidgarHTTPConfiguration(
                    appID: PayDayMidgar.tenantID, session: URLSession(configuration: configuration))))
    }

    static var capturedBody: String {
        String(decoding: captured?.httpBody ?? captured?.httpBodyStream.map(readAll) ?? Data(), as: UTF8.self)
    }

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

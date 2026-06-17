import Foundation
import PayDayKit

/// Worker-backed VAT validation. Conforms to the Kit protocol so view models
/// depend on the abstraction, not the transport. Always advisory — any failure
/// degrades to `unreachable` and never blocks issuing.
final class VATValidationService: VATValidating {
    private let client: WorkerClient
    init(client: WorkerClient = .shared) { self.client = client }

    private struct Body: Encodable { let vatID: String }

    func validate(vatID: String) async throws -> VATValidationResult {
        do {
            return try await client.post("v1/vat/validate", body: Body(vatID: vatID), as: VATValidationResult.self)
        } catch {
            AppLogger.shared.warn("VAT validation unreachable: \(error)", category: .vat)
            return .unreachable(vatID)
        }
    }
}

/// Worker-backed Peppol transmission. The send is metered (credits) by the
/// caller before transmitting; here we only broker through the worker gateway.
final class PeppolService: PeppolTransmitting {
    private let client: WorkerClient
    init(client: WorkerClient = .shared) { self.client = client }

    private struct LookupBody: Encodable { let recipient: PeppolRecipient }
    private struct SendBody: Encodable {
        let ublXML: String
        let recipient: PeppolRecipient
        let invoiceNumber: String
        let idempotencyKey: String
    }
    private struct SendResponse: Decodable {
        let status: String
        let transmissionID: String?
        let reason: String?
    }

    func lookup(endpointID: String, schemeID: String) async throws -> PeppolReachability {
        let recipient = PeppolRecipient(endpointID: endpointID, schemeID: schemeID, countryCode: "")
        return try await client.post("v1/peppol/lookup", body: LookupBody(recipient: recipient), as: PeppolReachability.self)
    }

    func send(ublXML: String, invoiceNumber: String, recipient: PeppolRecipient) -> AsyncThrowingStream<PeppolSendEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.validating)
                continuation.yield(.submitting)
                do {
                    let body = SendBody(
                        ublXML: ublXML,
                        recipient: recipient,
                        invoiceNumber: invoiceNumber,
                        idempotencyKey: "\(invoiceNumber)|\(recipient.endpointID)")
                    let response = try await client.post("v1/peppol/send", body: body, as: SendResponse.self)
                    if response.status == "accepted", let id = response.transmissionID {
                        continuation.yield(.accepted(transmissionID: id))
                        continuation.yield(.delivered(transmissionID: id))
                    } else {
                        continuation.yield(.failed(reason: response.reason ?? "unknown"))
                    }
                    continuation.finish()
                } catch let WorkerClient.WorkerError.http(_, reason) where reason != nil {
                    continuation.yield(.failed(reason: reason ?? "unknown"))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(reason: error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Worker-backed ECB exchange rates, display-only.
final class ExchangeRateService: ExchangeRateProviding {
    private let client: WorkerClient
    init(client: WorkerClient = .shared) { self.client = client }

    private struct RateResponse: Decodable { let rate: Double }

    func rate(from base: String, to quote: String) async throws -> Decimal {
        let response = try await client.get("v1/fx/rates?base=\(base)&quote=\(quote)", as: RateResponse.self)
        return Decimal(response.rate)
    }
}

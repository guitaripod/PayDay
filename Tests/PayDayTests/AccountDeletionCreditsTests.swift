import Foundation
import MidgarCommerce
import MidgarCore
import MidgarCredits
import Testing
@testable import PayDay

extension StoreBacked {
    /// Delete Account's remote steps with the wallet: the worker's records go first through the gateway, then the old
    /// per-app account at mako goes through `MidgarCredits.deleteLegacyAccount()`, which sends the api key as its only
    /// credential. A failure of either throws, which is what keeps the local data in place.
    @MainActor
    @Suite
    struct AccountDeletionWithCredits {
        private func makeWallet() -> MidgarCredits {
            CreditsGatewayStub.reset()
            return MidgarCredits(
                configuration: PayDayPacks.creditsConfiguration(isProductionLaunch: { false }),
                http: CreditsGatewayStub.httpConfiguration(),
                identity: StubIdentity(),
                purchasing: CancellingStore(),
                legacyAPIKey: { "legacy-key" }
            )
        }

        private func workerGateway(status: Int) -> PayDayGateway {
            CreditsGatewayStub.setWorkerDelete(.init(status: status, body: ""))
            return PayDayGateway(client: MidgarHTTPClient(configuration: CreditsGatewayStub.httpConfiguration()))
        }

        @Test func theWorkerIsDeletedThenTheLegacyAccountThroughTheWalletWithOnlyTheKey() async throws {
            let wallet = makeWallet()

            try await AccountService.deleteRemoteData(apiKey: "legacy-key", gateway: workerGateway(status: 204), credits: wallet)

            let worker = CreditsGatewayStub.requests(method: "DELETE", pathSuffix: "/v1/account")
            #expect(worker.count == 1)
            #expect(worker.first?.path == "/v1/payday/v1/account")
            #expect(worker.first?.header("Authorization") == "Bearer legacy-key")
            let deletes = CreditsGatewayStub.requests(method: "DELETE", pathSuffix: "/v1/identity")
            let request = try #require(deletes.first)
            #expect(deletes.count == 1)
            #expect(request.header("Authorization") == "Bearer legacy-key")
            #expect(request.header("X-Midgar-Token") == nil)
            await wallet.stop()
        }

        @Test func aWorkerFailureStopsBeforeTheWalletIsAsked() async {
            let wallet = makeWallet()

            await #expect(throws: AccountService.AccountError.self) {
                try await AccountService.deleteRemoteData(apiKey: "legacy-key", gateway: workerGateway(status: 503), credits: wallet)
            }

            #expect(CreditsGatewayStub.requests(method: "DELETE", pathSuffix: "/v1/identity").isEmpty)
            await wallet.stop()
        }

        @Test(arguments: [200, 204, 401, 404])
        func anAccountThatIsGoneOrAKeyMakoRejectsCountsAsDeleted(status: Int) async throws {
            let wallet = makeWallet()
            CreditsGatewayStub.setLegacyDelete(.init(status: status, body: "{}"))

            try await AccountService.deleteLegacyAccount(apiKey: "legacy-key", gateway: workerGateway(status: 204), credits: wallet)

            await wallet.stop()
        }

        @Test func aServerFailureThrowsItsStatusSoTheLocalDataStays() async {
            let wallet = makeWallet()
            CreditsGatewayStub.setLegacyDelete(.error(status: 500, code: "boom", message: "boom"))

            do {
                try await AccountService.deleteLegacyAccount(apiKey: "legacy-key", gateway: workerGateway(status: 204), credits: wallet)
                Issue.record("expected a server error")
            } catch let AccountService.AccountError.serverError(status) {
                #expect(status == 500)
            } catch {
                Issue.record("unexpected error \(error)")
            }
            await wallet.stop()
        }

        @Test func aWalletThatCannotBeReachedThrowsServiceUnavailable() async {
            let wallet = makeWallet()
            CreditsGatewayStub.setLegacyDelete(.error(status: 503, code: "wallet_unavailable", message: "later"))

            do {
                try await AccountService.deleteLegacyAccount(apiKey: "legacy-key", gateway: workerGateway(status: 204), credits: wallet)
                Issue.record("expected a server error")
            } catch let AccountService.AccountError.serverError(status) {
                #expect(status == 503)
            } catch {
                Issue.record("unexpected error \(error)")
            }
            await wallet.stop()
        }

        @Test func aHostWithoutAWalletDeletesTheLegacyAccountThroughTheGateway() async throws {
            CreditsGatewayStub.reset()
            let gateway = PayDayGateway(client: MidgarHTTPClient(configuration: CreditsGatewayStub.httpConfiguration()))

            try await AccountService.deleteLegacyAccount(apiKey: "key", gateway: gateway, credits: nil)

            let deletes = CreditsGatewayStub.requests(method: "DELETE", pathSuffix: "/v1/identity")
            #expect(deletes.count == 1)
            #expect(deletes.first?.path == "/v1/intelligence/v1/identity")
            #expect(deletes.first?.header("Authorization") == "Bearer key")
        }
    }
}

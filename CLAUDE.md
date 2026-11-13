# Pay Day

Native UIKit iOS invoice and estimate app for EU freelancers, wedged on e-invoicing compliance: free invoices for everyone, Pro adds Factur-X / ZUGFeRD hybrid PDFs (PDF/A-3 with embedded EN 16931 CII XML) and Peppol delivery.
`DESIGN.md` is the authoritative architecture, data model and EN 16931 / Factur-X plan.

## Layout

- `Core/PayDayCore/Sources/PayDayCore`: platform-agnostic Swift 6 (`Money`, `Invoice` model, `TaxEngine`, `CIIInvoiceWriter`, `UBLInvoiceWriter`, `InvoiceValidator`); no UIKit, PDFKit or Combine, builds on Linux and macOS
- `App/` and `Features/` (xcodegen, programmatic UIKit, MVVM, Darwin only): `DatabaseManager` (GRDB), actor repositories, `InvoicePDFRenderer` + `FacturXEmbedder`, `AICreditsManager`, `PeppolService`, `VATValidationService`, `App/PayDayMidgar`, `Services/PayDayGateway`, `Logging/LogCategories.swift`
- `services/pay-day` at the repo root (`payday-worker`): Cloudflare Workers, Hono v4, jose v6, KV + D1, TypeScript, vitest. SIWA to HS256 JWT, `/v1/vat/validate` (VIES), `/v1/fx/rates` (ECB), `/v1/peppol/send` and `/lookup`, `DELETE /v1/account`
- mako (`https://api.midgarcorp.cc/v1/intelligence`) owns identity, credits wallet, purchase validation and AI `run`. The payday-worker owns VIES, FX and Peppol. Do not confuse them.

## Build, test, deploy (Mac only, use the scripts)

```bash
scripts/setup.sh         # one-time: .env.local + xcodegen + spm
scripts/ios-build.sh     # build, with xcodegen + staleness assertion
scripts/ios-deploy.sh    # build + install + relaunch on PAYDAY_DEVICE_UDID
scripts/ios-test.sh      # PayDayCore (SPM) + hosted iOS tests on a simulator
swift test --package-path Core/PayDayCore  # PayDayCore only, runs anywhere
cd workers
npm install && npm run typecheck && npm test
CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare-api-token) npx wrangler deploy   # prod
```

- Never call `xcodebuild` raw. `ios-build.sh` runs `xcodegen generate` first, asserts no `.swift` is newer than the binary; adding or removing a file just means running it.
- Logs: `MidgarLog` writes `Library/Logs/payday.log` (rotates at 2 MB). Pull with the `ios-device-logs` skill or `devicectl ... copy from --source Library/Logs/payday.log`. Never log invoice contents, prompts or model output; never `print`.

## Rules that break things

- MidgarKit and AICredits come from the monorepo's `packages/MidgarKit` and `packages/AICredits` by path (`project.yml`, D15). The app links the `MidgarKit` umbrella product. Do not reimplement credits or purchases: MidgarStore and MidgarCredits sell, AICredits only runs the AI calls and holds the old account.
- Commerce engine is `storekit2`, entitlement `pro`: `PayDayMidgar.store` (a `MidgarStore`, mode purchases) sells the two Pro plans (annual `com.guitaripod.payday.pro.annual` $39.99 with a 7-day free trial, monthly `com.guitaripod.payday.pro.monthly` $4.99, both granting `pro`) and the four consumable packs, and `PayDayMidgar.credits` (a `MidgarCredits`) holds the balance on the Midgar ID wallet; both are nil in a test host or a demo capture (`reachesMidgarServices`). `App/Credits/PayDayPacks.swift` is the one table the configurations and the tests read: `starter` 30 credits $2.99, `regular` 110 $9.99, `propack` 300 $24.99, `business` 650 $49.99, products `com.guitaripod.payday.credits.<id>` (mako requires its `rc_product_prefix` plus the pack id). Never change product ids, prices or credit amounts without the founder. A purchase carries the Midgar ID as `appAccountToken`; MidgarCredits posts a pack's signed transaction to mako's validate route, which credits the wallet under the key the webhook shares, so a credit lands once. MidgarCredits runs in legacy-key mode (`legacyAPIKey` is `AICreditsManager.legacyAPIKey()`), so the balance from before the move stays linked. RevenueCat is gone from the app. mako's premium checks need nothing from the app: it asks the purchase ledger for the Midgar ID first and RevenueCat by mako user id second (old subscriptions).
- Pro: `ProAccess` (`App/Store/`) is the observable Pro model. `isPro` is `store.isEntitled(to: "pro")`, refreshed on the store's `entitlementsChanged` and `purchaseApproved`, after a purchase and a restore and when Settings and the Preview ask; the store's entitlements include StoreKit's current entitlements, so a Pro owner stays Pro offline, including every plan bought before the move. `PayDayMidgar.start()` queues those earlier plans for the ledger once per install (`reportPurchaseHistory()`). The paywall (`PaywallViewController`) reads plans, localized prices and trial eligibility from StoreKit through `ProAccess.loadPlans()`; Ask to Buy says Pro unlocks when approved and closes the paywall by itself when it does.
- Credits UI: `CreditsModel.shared` (`App/Credits/`) wraps MidgarCredits: the balance is read at launch, when the scene becomes active and after each AI draft and Peppol send, and follows `events()`; screens bind to its `balanceChanges`. The credit store is `PayDayCreditStoreView` on `PayDayCreditStoreModel` (`Features/Settings/`), opened from the Settings row, by an empty balance after a failed AI draft and by a Peppol send that needs more than the balance (`CreditsModel.peppolSendCost` is 30; the shortfall is shown). A credited purchase closes the store; Restore Purchases runs the App Store sync and reads the balance again. The Sign in with Apple row of the store still links the old account through `AICreditsManager.accountLink`. Demo captures use `DemoCreditsSource`. Apple Ads attribution is `MidgarCredits.reportAdAttributionOnce()` from `SceneDelegate`, only in a production launch (`PayDayMidgar.isProductionLaunch`).
- StoreKit testing: `Products.storekit` at the app root holds the plans and the packs and is the Run action's StoreKit configuration (`project.yml`). The `StoreBacked` suites (`CreditPurchases`, `ProPurchases`, `AccountDeletionWithCredits`) run serially against a `URLProtocol` stub of the gateway (`CreditsGatewayStub`). A purchase in the test host needs a window scene, which `SceneAnchoredStore` supplies; the first purchase on a fresh simulator can stall, so rerun once.
- Swift 6 complete checking; the app target has no MainActor default isolation, keep it that way unless the whole app moves.
- `keychain-access-groups` in `project.yml`: the app's own group first (AICredits keeps its api key there), `$(AppIdentifierPrefix)cc.midgarcorp.shared` second. No App Attest entitlement is needed.
- Gateway: `PayDayMidgar.intelligenceURL` is AICredits' base URL, the Midgar token goes through `additionalHeaders` (`midgarTokenHeaders()`, never waited on). The worker is `https://api.midgarcorp.cc/v1/payday/...`; `WorkerClient` sends the mako api key in `Authorization`, each call once with a 12 second timeout. Tenant id `payday`; Midgar ID, signals and portal use slug `pay-day`. Deploy the worker before the app release.
- Account deletion order in `AccountService.deleteAccount`: worker `DELETE /v1/payday/v1/account` first (needs the mako key), then the old mako account through `MidgarCredits.deleteLegacyAccount()` (the gateway delete when there is no wallet), then local data; a failure of either keeps the local data.
- Drafted payment reminder (`Features/Preview/ReminderFlow.swift`, `PayDayCore/Model/PaymentReminder.swift`): an overdue invoice's preview offers Draft a Reminder in three tones, one credit a draft. The instructions live on mako as the alias `reminder.draft.v1` (`tools/ai/aliases.json` and `prompts/`; `services/intelligence/scripts/gen_alias_sql.py apps/pay-day/tools/ai` writes the row, which is applied on arch), the app sends only the client's name and the invoice's number, amount and due date, and `PaymentReminder.draft` refuses a reply that misstates one of them or adds a figure, a percentage or a placeholder; a refused draft is asked for once more with `retry_of`, which mako does not charge. `PAYDAY_DEMO=reminder PAYDAY_DEMO_DOC=44 [PAYDAY_DEMO_TONE=firm]` opens the flow on the overdue demo invoice, and with a tone leaves the draft in the app's tmp folder as `reminder-draft.txt`.
- Privacy: `Resources/PrivacyInfo.xcprivacy`, `store/privacy-label.md` and the policy under `web/midgarcorp/src/content/legal/pay-day/` move together; policy URL `https://midgarcorp.cc/legal/pay-day/privacy/` (`LegalLinks`). No network exceptions in the registry.
- Secrets: `.env.local` (gitignored: `PAYDAY_BUNDLE_ID`, `PAYDAY_TEAM_ID`, `PAYDAY_DEVICE_UDID`, `PAYDAY_DEVICE_NAME`) and no app secrets: RevenueCat is gone, so `App/Secrets.swift` is no longer needed (an old one in a checkout is harmless). Worker secrets via `wrangler secret put` and `services/pay-day/.dev.vars`: `APP_JWT_SECRET`, `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `PEPPOL_API_KEY`, `PEPPOL_API_SECRET`, `PEPPOL_LEGAL_ENTITY_ID`; `wrangler.jsonc` vars `PEPPOL_PROVIDER`, `PEPPOL_GATEWAY_BASE`. If any required secret is missing the stub Peppol gateway silently runs. Never commit secrets.
- Money is integer minor units plus ISO-4217 code, never `Double`; rounding is half-up at the document boundary (EN 16931).
- The PDF and the EN 16931 XML render from one `Invoice` value so they never disagree.
- Never block issuing on the network: VIES, FX and Peppol degrade gracefully, offline invoicing must work.
- Peppol AS4 is brokered through the worker's gateway, never implemented on device. Free stays genuinely good (unlimited invoices, clients, multi-currency, full VAT); the paywall sits on compliance, delivery and automation.

## Conventions

- `final class`; `nonisolated struct: Sendable` for values; `@available(*, unavailable) required init?(coder: NSCoder) { fatalError() }` on every custom view/VC.
- Programmatic UIKit, no storyboards, `UIStackView` first then anchors. No Combine in `PayDayCore`: the `@MainActor` VM consumes streams in a `Task` and republishes via its own `PassthroughSubject<T, Never>` (never `@Published`); VCs bind in `viewDidLoad` with `Set<AnyCancellable>` and `.receive(on: DispatchQueue.main)`.
- GRDB: `nonisolated struct` records, `registerMigration("vN")`, never edited after release.
- Liquid Glass on iOS 26 with `.systemThinMaterial` fallback.
- No comments, no MARK, no file headers; SPM only; Swift Testing, never XCTest.

## More in docs/agent-notes.md

Stack detail, backend split, Midgar platform wiring, Peppol provider config, product reality (compliance wedge, store metadata lead), settings, review prompt, log categories (`app, auth, db, invoice, pdf, einvoice, peppol, vat, credits, ui`).

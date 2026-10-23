# Pay Day

Native UIKit iOS invoice and estimate app for EU freelancers, wedged on e-invoicing compliance: free invoices for everyone, Pro adds Factur-X / ZUGFeRD hybrid PDFs (PDF/A-3 with embedded EN 16931 CII XML) and Peppol delivery.
`DESIGN.md` is the authoritative architecture, data model and EN 16931 / Factur-X plan.

## Layout

- `Sources/PayDayKit`: platform-agnostic Swift 6 (`Money`, `Invoice` model, `TaxEngine`, `CIIInvoiceWriter`, `UBLInvoiceWriter`, `InvoiceValidator`); no UIKit, PDFKit or Combine, builds on Linux and macOS
- `PayDay/` (xcodegen, programmatic UIKit, MVVM, Darwin only): `DatabaseManager` (GRDB), actor repositories, `InvoicePDFRenderer` + `FacturXEmbedder`, `AICreditsManager`, `PeppolService`, `VATValidationService`, `App/PayDayMidgar`, `Services/PayDayGateway`, `Logging/LogCategories.swift`
- `services/pay-day` at the repo root (`payday-worker`): Cloudflare Workers, Hono v4, jose v6, KV + D1, TypeScript, vitest. SIWA to HS256 JWT, `/v1/vat/validate` (VIES), `/v1/fx/rates` (ECB), `/v1/peppol/send` and `/lookup`, `DELETE /v1/account`
- mako (`https://api.midgarcorp.cc/v1/intelligence`) owns identity, credits ledger, RevenueCat validation and AI `run`. The payday-worker owns VIES, FX and Peppol. Do not confuse them.

## Build, test, deploy (Mac only, use the scripts)

```bash
scripts/setup.sh         # one-time: .env.local + Secrets.swift + xcodegen + spm
scripts/ios-build.sh     # build, with xcodegen + staleness assertion
scripts/ios-deploy.sh    # build + install + relaunch on PAYDAY_DEVICE_UDID
scripts/ios-test.sh      # PayDayKit (SPM) + hosted iOS tests on a simulator
swift test               # PayDayKit only, runs anywhere
cd workers
npm install && npm run typecheck && npm test
CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare-api-token) npx wrangler deploy   # prod
```

- Never call `xcodebuild` raw. `ios-build.sh` runs `xcodegen generate` first, asserts no `.swift` is newer than the binary; adding or removing a file just means running it.
- Logs: `MidgarLog` writes `Library/Logs/payday.log` (rotates at 2 MB). Pull with the `ios-device-logs` skill or `devicectl ... copy from --source Library/Logs/payday.log`. Never log invoice contents, prompts or model output; never `print`.

## Rules that break things

- MidgarKit and AICredits come from the monorepo's `packages/MidgarKit` and `packages/AICredits` by path (`project.yml`, D15). The app links the `MidgarKit` umbrella product. Do not reimplement credits or RevenueCat: use AICredits.
- Commerce engine is `aicredits`, entitlement `pro`: AICredits and RevenueCat buy, restore and meter. Never change product ids, prices or the RevenueCat app user id without the founder.
- Swift 6 complete checking; the app target has no MainActor default isolation, keep it that way unless the whole app moves.
- `keychain-access-groups` in `project.yml`: the app's own group first (AICredits keeps its api key there), `$(AppIdentifierPrefix)cc.midgarcorp.shared` second. No App Attest entitlement is needed.
- Gateway: `PayDayMidgar.intelligenceURL` is AICredits' base URL, the Midgar token goes through `additionalHeaders` (`midgarTokenHeaders()`, never waited on). The worker is `https://api.midgarcorp.cc/v1/payday/...`; `WorkerClient` sends the mako api key in `Authorization`, each call once with a 12 second timeout. Tenant id `payday`; Midgar ID, signals and portal use slug `pay-day`. Deploy the worker before the app release.
- Account deletion order in `AccountService.deleteAccount`: worker `DELETE /v1/payday/v1/account` first (needs the mako key), then mako's identity delete, then local data.
- Privacy: `PayDay/PrivacyInfo.xcprivacy`, `store/privacy-label.md` and the policy under `web/midgarcorp/src/content/legal/pay-day/` move together; policy URL `https://midgarcorp.cc/legal/pay-day/privacy/` (`LegalLinks`). No network exceptions in the registry.
- Secrets: `.env.local` (gitignored: `PAYDAY_BUNDLE_ID`, `PAYDAY_TEAM_ID`, `PAYDAY_DEVICE_UDID`, `PAYDAY_DEVICE_NAME`) and gitignored `PayDay/Secrets.swift` (`revenueCatPublicKey`, from `Secrets.example.swift`). Worker secrets via `wrangler secret put` and `services/pay-day/.dev.vars`: `APP_JWT_SECRET`, `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `PEPPOL_API_KEY`, `PEPPOL_API_SECRET`, `PEPPOL_LEGAL_ENTITY_ID`; `wrangler.jsonc` vars `PEPPOL_PROVIDER`, `PEPPOL_GATEWAY_BASE`. If any required secret is missing the stub Peppol gateway silently runs. Never commit secrets.
- Money is integer minor units plus ISO-4217 code, never `Double`; rounding is half-up at the document boundary (EN 16931).
- The PDF and the EN 16931 XML render from one `Invoice` value so they never disagree.
- Never block issuing on the network: VIES, FX and Peppol degrade gracefully, offline invoicing must work.
- Peppol AS4 is brokered through the worker's gateway, never implemented on device. Free stays genuinely good (unlimited invoices, clients, multi-currency, full VAT); the paywall sits on compliance, delivery and automation.

## Conventions

- `final class`; `nonisolated struct: Sendable` for values; `@available(*, unavailable) required init?(coder: NSCoder) { fatalError() }` on every custom view/VC.
- Programmatic UIKit, no storyboards, `UIStackView` first then anchors. No Combine in `PayDayKit`: the `@MainActor` VM consumes streams in a `Task` and republishes via its own `PassthroughSubject<T, Never>` (never `@Published`); VCs bind in `viewDidLoad` with `Set<AnyCancellable>` and `.receive(on: DispatchQueue.main)`.
- GRDB: `nonisolated struct` records, `registerMigration("vN")`, never edited after release.
- Liquid Glass on iOS 26 with `.systemThinMaterial` fallback.
- No comments, no MARK, no file headers; SPM only; Swift Testing, never XCTest.

## More in docs/agent-notes.md

Stack detail, backend split, Midgar platform wiring, Peppol provider config, product reality (compliance wedge, store metadata lead), settings, review prompt, log categories (`app, auth, db, invoice, pdf, einvoice, peppol, vat, credits, ui`).

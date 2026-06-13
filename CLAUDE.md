# Pay Day — Agent Instructions

Native UIKit iOS **invoice & estimate app for EU freelancers and small businesses**, wedged on
**e-invoicing compliance**: free, beautiful invoices for everyone; **Pro** turns them into legally
compliant **Factur-X / ZUGFeRD** hybrid PDFs (a PDF/A-3 carrying embedded **EN 16931** CII XML) and
delivers them over the **Peppol** network. The competitive bet is the compliance wedge no mobile
incumbent ships — not the saturated "invoice maker" keyword.

See `DESIGN.md` for the authoritative architecture, the data model, the EN 16931 / Factur-X plan,
and the spikes that gate the build. This file is the working guide.

## Stack

- **PayDayKit** (`Sources/PayDayKit`): platform-agnostic Swift 6 — `Money`/`Currency` value types,
  the `Invoice`/`Party`/`LineItem` domain model, the **`TaxEngine`** (EN 16931 VAT categories +
  breakdown + monetary summation), **`CIIInvoiceWriter`** (Factur-X / EN 16931 CII XML) and
  **`UBLInvoiceWriter`** (Peppol BIS Billing 3.0 UBL), `InvoiceValidator` (BR-* business rules),
  `NumberSequence`, GRDB record structs, and **Sendable** protocols exposing `AsyncStream`. **No
  UIKit / PDFKit / Combine imports — compiles and tests on Linux and macOS via `swift build`.**
- **PayDay** (`PayDay/`, xcodegen): programmatic UIKit, MVVM. Combine `PassthroughSubject` lives
  **only** at the VM↔VC seam. `DatabaseManager` (GRDB `DatabaseQueue`), `actor` repositories,
  `InvoicePDFRenderer` + `FacturXEmbedder` (PDFKit/Core Graphics), `AICreditsManager` (mako),
  `PeppolService` + `VATValidationService` (Worker). Swift 6 strict concurrency, iOS 18+ deploy /
  iOS 26 SDK, iPhone-first (iPad-capable later). Darwin-only — build on a Mac.
- **workers/** (`payday-worker`): Cloudflare Workers (Hono v4, jose v6, KV + D1). Sign in with Apple
  → HS256 app JWT; `/v1/vat/validate` (EU VIES bridge), `/v1/fx/rates` (ECB), `/v1/peppol/send` +
  `/v1/peppol/lookup` (access-point gateway broker — pluggable, stubbed). TypeScript, vitest.
- **mako** (`mako.midgarcorp.cc`): the shared AI-credits backend via the **AICredits** SPM package
  (`AICreditsCore`/`AICreditsRevenueCat`/`AICreditsUI`). Identity, credits ledger, RevenueCat
  validation, AI capability `run`. App-ID `payday`. Do not reimplement credits — use AICredits.

## Backend split (do not confuse the two)

- **mako / AICredits** owns identity, the credits ledger, RevenueCat purchase validation, and the AI
  hot path (`/v1/run/*`). Entitlement `pro`. Reuse the package; never hand-roll RevenueCat.
- **payday-worker** owns the invoice-domain services that need server secrets or CORS-free access:
  VIES VAT validation, ECB FX rates, and Peppol AS4 transmission through an access-point gateway.
  It authenticates with the same SIWA→JWT used for cross-device sync.

## Code style (non-negotiable)

- `final class` for classes; `nonisolated struct: Sendable` for value types.
- `@available(*, unavailable) required init?(coder: NSCoder) { fatalError() }` on every custom view/VC.
- Programmatic only — no storyboards/XIB. `UIStackView` first, then anchors.
- Core surfaces expose `AsyncStream`/`AsyncSequence` and **Sendable** protocols — no Combine in
  `PayDayKit`. The `@MainActor` VM consumes streams in a `Task` and republishes via its own
  `PassthroughSubject<T, Never>` (never `@Published`); VCs bind in `viewDidLoad`, hold
  `Set<AnyCancellable>`, `.receive(on: DispatchQueue.main)`.
- Service protocols in `PayDayKit` where platform-agnostic; concrete singletons (`.shared`) injected
  through inits with defaults.
- GRDB: `nonisolated struct` records, `DatabaseMigrator.registerMigration("vN")`, never edited after
  release. On-device only — business + client data never leaves the phone except what the user sends.
- Money is **integer minor units + ISO-4217 code**, never `Double`. All rounding is half-up at the
  document boundary, per EN 16931.
- `UIBackgroundConfiguration.listCell()` on list cells. SF Symbol effects (`.bounce`/`.replace` on
  status change, `.pulse` on processing). Liquid Glass (`UIGlassEffect`/`UIGlassContainerEffect`) on
  iOS 26, `.systemThinMaterial` fallback on iOS 18.
- No comments, no MARK, no file headers. `///` doc comments sparingly. SPM only.
- Swift Testing (`@Test`, `#expect`) — never XCTest.

## Build & deploy — use the scripts (Mac only)

xcodegen regenerates `PayDay.xcodeproj` from `project.yml` on every build, so:

```bash
scripts/setup.sh         # one-time: .env.local + Secrets.swift + xcodegen + spm
scripts/ios-build.sh     # build, with xcodegen + staleness assertion
scripts/ios-deploy.sh    # build + install + relaunch on PAYDAY_DEVICE_UDID
scripts/ios-test.sh      # PayDayKit (SPM) + hosted iOS tests on a simulator
swift test               # PayDayKit only — runs anywhere, no Xcode/device needed
```

`ios-build.sh` runs `xcodegen generate` first, captures the real xcodebuild exit code via
`pipefail`, surfaces Swift 6 concurrency errors, and asserts no `.swift` is newer than the built
binary. Adding/removing any file → just run `ios-build.sh`. Never call `xcodebuild` raw.

```bash
cd workers
npm install && npm run typecheck && npm test
CLOUDFLARE_API_TOKEN=$(cat ~/.cloudflare-api-token) npx wrangler deploy   # prod
```

## Logging — agents read this

`AppLogger` mirrors os_log AND `Library/Logs/payday.log` (rotates at 2 MB). Categories:
`app, auth, db, invoice, pdf, einvoice, peppol, vat, credits, ui`. Pull from a device with the
`ios-device-logs` skill / `devicectl ... copy from --source Library/Logs/payday.log`.

## Secrets / config

`.env.local` (gitignored, made by `setup.sh`): `PAYDAY_BUNDLE_ID`, `PAYDAY_TEAM_ID`,
`PAYDAY_DEVICE_UDID`, `PAYDAY_DEVICE_NAME`. `PayDay/Secrets.swift` (gitignored, from
`Secrets.example.swift`): `workerBaseURL`, `makoBaseURL`, `revenueCatPublicKey`, `redirectURI`.
Worker secrets via `wrangler secret put` (prod) + `workers/.dev.vars` (local): `APP_JWT_SECRET`,
`APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `PEPPOL_API_KEY`, `PEPPOL_GATEWAY_BASE`. Never commit any.

## Reality

- **The wedge is compliance, not the keyword.** Lead store metadata with "EU e-invoicing / Peppol /
  Factur-X / EN 16931", not "invoice maker" — both for ASO differentiation and App Review 4.3.
- **Free must be genuinely good.** Unlimited invoices, clients, logo, multi-currency, full VAT math.
  The paywall sits on compliance + delivery + automation, which is where the proven money is and the
  only place we should ask freelancers to pay.
- **Never block issuing on the network.** VIES, FX, and Peppol lookups degrade gracefully —
  validation is advisory; a freelancer offline on a job site must still produce an invoice.
- **The XML and the PDF come from one `Invoice` value.** Render the human PDF and the EN 16931 XML
  from the same source so a Pro e-invoice can never show different numbers to human and machine.
- **Peppol AS4 is brokered, never hand-rolled.** The worker calls a pluggable access-point gateway;
  we are not an access point and do not implement AS4/SML/SMP on device.

# Pay Day — Design

Authoritative architecture for **Pay Day**, a native UIKit iOS **invoice & estimate app for EU
freelancers and small businesses**, wedged on **e-invoicing compliance** (EN 16931 / Factur-X /
ZUGFeRD / Peppol BIS Billing 3.0) — the structured-invoice capability that no mobile incumbent
ships. You create a client, build an invoice from line items, and export a beautiful PDF; Pro turns
that same PDF into a **legally compliant hybrid e-invoice** (a PDF/A-3 carrying embedded EN 16931
CII XML) and can deliver it over the **Peppol network**.

The competitive thesis (validated 2026-06-12, see the competitor-hunt memory): the "invoice maker"
keyword is owned by 4.7★/100k-rating incumbents (Invoice Simple ≈ $2M/mo) we will not out-rank
head-on — but **none of them ship EN 16931 / Peppol on mobile**, EU mandates are rolling out
(Belgium all-business live 2026-01, France PDP 2027-09, Germany B2B receive-mandate live, Poland
KSeF), and the per-send Peppol cost (≈ €0.18–0.25) maps cleanly onto our existing credits backend.
So we compete on the wedge, not the keyword.

## Status

Greenfield — foundation scaffolded. **PayDayKit (the EN 16931 CII + Peppol UBL generators and the
VAT engine) is the differentiated, fully unit-tested core and builds on Linux/macOS via
`swift build`.** The UIKit app, the PDF/A-3 Factur-X embedder, and the Cloudflare Worker (VIES VAT
validation + Peppol access-point broker) build on top. The Peppol AS4 transmission is brokered
through a pluggable access-point gateway (stubbed; Storecove-shaped adapter ready) — never
hand-rolled AS4 on device.

## Product shape

- **One operator, B2B output.** A freelancer/contractor creates invoices and estimates, tracks
  payment status, and exports/sends them. No two-sided marketplace, no network effects, no licensed
  data — a single excellent native dev reaches parity and surpasses on compliance + craft.
- **Free tier is generous** (this is a switcher play): unlimited invoices + estimates, unlimited
  clients, professional PDF export with your own logo, multi-currency, the full VAT engine. We do
  not cripple the basics — incumbents already do, and that is the complaint we exploit.
- **Pro (subscription)** unlocks the wedge: compliant **Factur-X / ZUGFeRD** PDF/A-3 e-invoices,
  **Peppol** delivery, recurring invoices, custom templates/accent branding, VIES VAT-number
  validation, CSV/accounting export, and overdue automation.
- **Credits (consumable, metered via mako)** cover genuinely per-unit costs: each **Peppol send**
  (pay-per-use at the access point) and each **AI action** — photo/receipt → drafted line items,
  natural-language → invoice, and tone-adjustable payment-reminder drafting.

## Architecture (the seam)

```
                         ┌──────────────────────────────────────────┐
                         │ PayDayKit  (platform-agnostic, Swift 6)    │
   pure value types  ←→  │  Money · Currency · Invoice · Party        │
   no UIKit/PDFKit       │  TaxEngine (EN 16931 VAT categories)       │
   builds on Linux       │  CIIInvoiceWriter  (Factur-X / EN16931)    │
                         │  UBLInvoiceWriter  (Peppol BIS 3.0)        │
                         │  InvoiceValidator  (BR-* business rules)   │
                         │  NumberSequence · GRDB record structs      │
                         │  Sendable protocols (AsyncStream surface)  │
                         └────────────────────┬───────────────────────┘
                                              │ depends on
                         ┌────────────────────┴───────────────────────┐
                         │ PayDay (app, programmatic UIKit, MVVM)       │
   @MainActor VM   ───→  │  DatabaseManager (GRDB) + Repositories       │
   PassthroughSubject    │  DesignSystem (tokens, glass, factories)     │
   at VM↔VC seam only    │  InvoicePDFRenderer → FacturXEmbedder        │
                         │  AICreditsManager (mako) · PeppolService     │
                         │  VCs: Dashboard·Invoices·Editor·Clients·     │
                         │       Preview·Settings·Paywall·Onboarding    │
                         └────────────────────┬───────────────────────┘
                                              │ HTTPS (authed)
            ┌─────────────────────────────────┴─────────────────────────┐
            │ workers/payday-worker (Hono, Cloudflare)                    │
            │  SIWA → app JWT (sync identity)                             │
            │  /v1/vat/validate   → EU VIES SOAP bridge                   │
            │  /v1/fx/rates       → ECB reference rates (cached)          │
            │  /v1/peppol/send    → access-point gateway (AS4 broker)     │
            │  /v1/peppol/lookup  → SML/SMP participant lookup            │
            └─────────────────────────────────────────────────────────────┘
                                              │
            mako.midgarcorp.cc (shared AI-credits backend, AICredits SPM) ──┘
            credits ledger · RevenueCat validation · AI capability run
```

The VM↔VC contract is identical to Psybeam/DreamEater: the `@MainActor` view model holds its
domain state and republishes changes to the view controller via its own
`PassthroughSubject<T, Never>` (never `@Published`); the VC subscribes in `viewDidLoad`, stores
`Set<AnyCancellable>`, and `.receive(on: DispatchQueue.main)`. Repositories are an `actor` over the
GRDB `DatabaseQueue`; the VM consumes their `async` reads/writes from a `Task`.

## Data model (GRDB, on-device; structs in PayDayKit)

- `Business` — the user's own company (seller): legal name, address, VAT id, IBAN/BIC, tax scheme,
  logo, default currency, payment terms, invoice/estimate number sequences. One row (the operator).
- `Client` — buyer parties: legal name, contact, address, VAT id / Peppol participant id, country.
- `Document` — the invoice or estimate: type (`invoice` / `estimate` / `credit_note`), number,
  issue date, due date, currency, status (`draft`/`sent`/`viewed`/`paid`/`overdue`/`void`),
  client reference, notes, payment terms, accent color, and a denormalized totals snapshot.
- `LineItem` — name, description, quantity, unit, unit price, discount, VAT category + rate, and a
  computed net. Ordered within a document.
- `Payment` — recorded settlements against a document (amount, date, method) for partial-payment
  tracking.
- `NumberSequence` — per-type monotonic counters with a format template (e.g. `INV-{YYYY}-{seq:04}`).

Migrations: `DatabaseMigrator.registerMigration("v1")`, never edited after release. Money is stored
as **integer minor units** (cents) + ISO-4217 currency code — never `Double` columns.

## EN 16931 / Factur-X (the differentiator)

- **CIIInvoiceWriter** emits UN/CEFACT **Cross-Industry Invoice** (CII, D16B) XML conforming to the
  **EN 16931** semantic model — the `urn:cen.eu:en16931:2017` guideline id, the
  `urn:factur-x.eu:1p0:basic` / `…:en16931` profile, all mandatory **BT-** business terms, the
  `ApplicableHeaderTradeSettlement` VAT breakdown, and the monetary summation. This is the file
  embedded in the hybrid PDF.
- **UBLInvoiceWriter** emits **Peppol BIS Billing 3.0** UBL 2.1 `Invoice` / `CreditNote` for network
  delivery (customization id `urn:cen.eu:en16931:2017#compliant#urn:fdc:peppol.eu:2017:poacc:billing:3.0`).
- **FacturXEmbedder** (app layer, Core Graphics/PDFKit) wraps the rendered visual PDF as **PDF/A-3**
  with the CII XML embedded as an **associated file** (`AFRelationship /Data`, name `factur-x.xml`)
  plus the required Factur-X **XMP** extension schema. The visual layout and the XML are generated
  from the same `Invoice` value, so they can never disagree.
- **InvoiceValidator** enforces the load-bearing EN 16931 business rules (BR-CO-10/13/15 monetary
  summation, BR-S/-Z/-E/-AE VAT-category rules, BR-CO-9 VAT-id format, exactly-one buyer/seller,
  reverse-charge and intra-community exemption notes) before any document can be marked compliant.

## Monetization

- RevenueCat via the **AICredits** SPM package (`AICreditsCore`/`AICreditsRevenueCat`/`AICreditsUI`),
  exactly as Psybeam/DreamEater. Entitlement `pro`. Subscription group "Pay Day Pro": monthly
  €4.99, annual €39.99 (7-day trial). Lifetime one-time also offered.
- Credits packs (consumable IAP) validated server-side by mako
  (`/v1/credits/purchase/revenuecat/validate`, product↔pack bound). Peppol send = N credits;
  AI action = N credits. Free tier never needs credits for local PDF export.

## App Review gates

- **4.3 (spam):** the invoice-maker category is crowded — we lead screenshots and copy with the
  **e-invoice / Peppol compliance** angle, not "make an invoice", to read as a distinct product.
- **3.1.1 / IAP:** all unlocks are StoreKit IAP; no external purchase links in-app.
- **5.1.1 (data):** business/client data is on-device (GRDB); the worker only sees what the user
  explicitly sends (a VAT id to validate, an invoice to transmit). Privacy page at
  `https://mako.midgarcorp.cc/privacy/payday`. **China availability OFF** (no metadata AI-string risk).
- **2.1 (completeness):** seed demo data + a sample invoice so reviewers see output immediately.

## Spikes (gate the build)

1. **PDF/A-3 + embedded associated file on iOS.** Can we attach `factur-x.xml` with
   `AFRelationship` and emit valid Factur-X XMP using `UIGraphicsPDFRenderer` + CGPDF, or do we need
   a minimal PDF post-processor? (Validate output against the Mustangproject / FNFE validator.)
2. **Peppol access-point broker.** Confirm a pay-per-use AP (Storecove / Tickstar) with a clean REST
   surface and no monthly minimum, so the worker brokers AS4 without us operating an AP.
3. **VIES reliability.** The EU VIES endpoint is flaky; confirm the worker caches and degrades
   (validation is advisory, never blocks issuing an invoice).

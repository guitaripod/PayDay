# Pay Day — Store playbook

App Store Connect + RevenueCat + release mechanics for Pay Day. Read
`~/.config/midgar/OPERATIONS.md` first; this file is the per-app specifics.
The decided launch metadata/pricing/copy lives in `docs/launch-spec.md`.

## 0. Baseline / identity

- Bundle `com.guitaripod.payday` (registered, id `AL4DRY5YYV`, SIWA enabled). App Store id `6779927672`;
  app shell created in ASC web UI (Apple forbids app-record CREATE via API). Vendor `93803823`.
- RC project: TODO (create in dashboard; add `RC_SECRET_PAYDAY` to credentials.env). Entitlement `pro`.
- mako tenant `payday` (credit packs + capability costs seeded per launch-spec credit costing).
- No revenue to protect; pre-launch.

## Gates (evaluated weekly by /revenue-ops)

Benchmarks to beat (RevenueCat/Adapty 2026; B2B-tool buyers run higher WTP than consumer):
download→trial ~7% · trial→paid ≥35% · ~82% buy the defaulted (annual) plan.

- **Day 30**: ≥300 downloads AND ≥5 trial starts → hold course. <50 downloads = visibility problem →
  iterate ASO (subtitle/keywords/screenshot 1 = the compliance hero) before any product work. This is
  an ASO bet on the e-invoice/Peppol wedge; if compliance keywords don't pull, re-cut the listing.
- **Day 60**: trial→paid ≥35% → press: annual win-back + push recurring invoices; watch credit-pack
  attach (Peppol-send demand = the B2B value signal). <20% → lengthen trial to 14 days before prices.
- **Day 90**: proceeds ≥€150/mo → experiment cadence, **localization first** (EU app: DE/FR/FI/NL
  listings are the top win lever). Proceeds ≈0 with healthy funnel top → fix positioning, not pricing.
  **Never ship features to fix a funnel.**
- Standing: reply to every review within 48h; append `docs/metrics.csv` weekly; one decision/episode.
- Watch: Peppol-send allowance burn (annual 60/yr, monthly 5/mo, server-granted) — if heavy-sender COGS
  exceeds retained revenue, cut 60→40 via the mako promo grant (no metadata change).

## ASO (lead with the wedge, not "invoice maker")

- Title/subtitle keywords: **e-invoice, Factur-X, ZUGFeRD, Peppol, EN 16931, EU VAT, e-lasku,
  e-Rechnung, facturation électronique**. These are low-competition and intent-rich; the saturated
  "invoice maker" terms are secondary.
- Screenshots lead with the **compliance moment** (the "✓ EN 16931 compliant" preview + Peppol send),
  then the clean invoice, then "free & unlimited". This also reads as a distinct product for
  App Review 4.3 (do not look like another template invoice app).

## Monetization (RevenueCat)

- Entitlement `pro`. Subscription group "Pay Day Pro": monthly €4.99, annual €39.99 (7-day trial),
  plus a lifetime one-time unlock.
- Consumable credit packs (Peppol sends + AI). Validated server-side by mako
  (`/v1/credits/purchase/revenuecat/validate`, product↔pack bound) — never grant on customer
  existence alone (the PixiePocket lesson).
- Map both subs to `pro`; also derive all-access from CustomerInfo as a belt-and-suspenders fallback.

## App Review gates

- **4.3 spam:** lead with compliance, per ASO above.
- **3.1.1 IAP:** all unlocks are StoreKit; no external purchase links.
- **2.1 completeness:** first launch seeds a configured business, two clients, and two worked
  invoices (`DemoSeeder`) so a reviewer sees real output and can generate a PDF immediately.
- **5.1.1 data:** business/client data is on-device (GRDB). The worker only receives what the user
  explicitly sends (a VAT id to validate, a UBL to transmit). Privacy page:
  `https://mako.midgarcorp.cc/privacy/payday`. **China availability OFF.**

## Release CI

- `.github/workflows/release.yml` — `macos-26` runner, beta-host guard (ITMS-90111), manual signing
  (p12 + provisioning profile "PayDay App Store 2026"), Secrets.swift materialized inline, IPA zipped
  by hand, `altool --upload-app`. Repo secrets: SIGNING_P12_BASE64, P12_PASSWORD,
  PROVISIONING_PROFILE_BASE64, ASC_API_KEY_P8_BASE64, AICREDITS_DEPLOY_KEY, REVENUECAT_PUBLIC_KEY.
- Mint the provisioning profile via `POST /v1/profiles` (bundle `com.guitaripod.payday` + cert
  WXA29XJHK2). The app uses Sign in with Apple → enable APPLE_ID_AUTH on the bundle id first.

## Spikes

1. **PDF/A-3 Factur-X validation — DONE (2026-06-13).** `FacturXEmbedder` output passes
   Mustangproject: `Parsed PDF:valid XML:valid`, PDF/A-3b + EN 16931. Repeatable via
   `scripts/validate-facturx.sh` (runs the hosted export test on a sim, validates with the bundled
   Mustang CLI). Re-run it after any change to `InvoicePDFRenderer` or `FacturXEmbedder`; it must stay
   green before shipping. Lone Mustang item `BR-DE-21` is a NOTICE (XRechnung CIUS identifier) — not
   an error for pan-EU/Peppol core EN 16931. Compliant Factur-X export is Pro-gated; free users get a
   clean visual PDF.
2. **Peppol access point — OPEN (needs your account).** Sign up at recommand.eu (free tier:
   25 docs/mo, no setup fee) or e-invoice.be (~€0.18/send, no minimum). No OpenPeppol membership or
   certification needed to send via a reseller AP. Set `PEPPOL_API_KEY` + `PEPPOL_LEGAL_ENTITY_ID`
   (+ `PEPPOL_GATEWAY_BASE`) as worker secrets; `makePeppolGateway` switches off the stub once set.
   Per-send cost is metered to the user as credits.
3. **VIES reliability** — worker caches and degrades; VAT validation is always advisory, never blocks
   issuing.

## Known fast-follows (post-1.0, not blockers)

- Logo upload in Business settings (renderer already accepts `style.logo`).
- Recurring invoices + partial-payment ledger (today: mark-paid).
- Localization pass (EU markets) and a VoiceOver/Dynamic-Type accessibility audit.
- Live Recommand adapter once the API key exists (Storecove-shaped adapter + stub are in `lib/peppol.ts`).

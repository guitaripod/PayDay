# Pay Day

A native iOS invoice & estimate app for EU freelancers and small businesses — beautiful invoices
for free, and **legally compliant e-invoices** (Factur-X / ZUGFeRD / Peppol BIS Billing 3.0) when
you need them. Built in modern programmatic UIKit on a platform-agnostic Swift 6 core.

The wedge: the "invoice maker" keyword is owned by entrenched incumbents we won't out-rank head-on,
but **none of them ship EN 16931 / Peppol on mobile**, and EU e-invoicing mandates are rolling out
(Belgium 2026, France 2027, Germany, Poland). Pay Day competes on compliance, not the keyword.

## Layout

```
Sources/PayDayKit/   Platform-agnostic core (builds on Linux/macOS via `swift build`)
  Model/             Money, Currency, Invoice, Party, LineItem, VATCategory, …
  Tax/               TaxEngine (EN 16931 VAT breakdown + monetary summation)
  EInvoice/          CIIInvoiceWriter (Factur-X), UBLInvoiceWriter (Peppol), InvoiceValidator
PayDay/              UIKit app (MVVM, GRDB, PDFKit renderer + Factur-X embedder, AICredits, services)
workers/             Cloudflare Worker (Hono): VIES VAT, ECB FX, Peppol gateway broker
Tests/ PayDayTests/  PayDayKit (SPM) + hosted iOS rendering tests
```

See `CLAUDE.md` for working conventions and `DESIGN.md` for the authoritative architecture.

## Build & test

```bash
swift test                  # PayDayKit — runs anywhere, no Xcode/device
scripts/setup.sh            # one-time: .env.local + Secrets.swift + xcodegen + spm (Mac)
scripts/ios-build.sh        # build the app with staleness assertion (Mac)
scripts/ios-test.sh         # PayDayKit + hosted iOS tests (Mac)
cd workers && npm install && npm run typecheck && npm test
```

## Monetization

Free: unlimited invoices/estimates, logo, multi-currency, the full VAT engine. **Pro** (subscription)
unlocks compliant Factur-X PDFs, Peppol delivery, recurring invoices, branding, and VAT validation.
**Credit packs** (consumable) meter per-Peppol-send cost and AI actions, via the shared mako backend.

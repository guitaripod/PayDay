# Pay Day

Invoices and estimates for EU freelancers and small businesses on iPhone. Making and sending invoices is free. Pro adds legally compliant e-invoices: Factur-X / ZUGFeRD hybrid PDFs (PDF/A-3 with embedded EN 16931 XML) and delivery over the Peppol network (BIS Billing 3.0), as EU e-invoicing mandates arrive.

## What it does

- Invoices and estimates with your logo, any currency and an EN 16931 VAT engine (reverse charge, exemptions, per-rate breakdown)
- EU VAT number checks against VIES and ECB exchange rates
- Pro (monthly or annual): Factur-X PDFs, Peppol sending, recurring invoices and branding
- Credit packs pay for Peppol sends and AI drafting, on the person's Midgar ID wallet

## Layout

```
Core/PayDayCore/      Swift package, platform agnostic (builds and tests on Linux)
  Model/              Money, Currency, Invoice, Party, LineItem, VATCategory
  Tax/                TaxEngine: EN 16931 VAT breakdown and totals
  EInvoice/           CII (Factur-X) and UBL (Peppol) writers, InvoiceValidator
App/ Features/        programmatic UIKit app (XcodeGen, MVVM, GRDB), PDF renderer and Factur-X embedder
Resources/            string catalog, assets, privacy manifest
Tests/PayDayTests/    hosted iOS tests
```

The backend is `services/pay-day` in the Midgar monorepo, a Cloudflare Worker for VIES, exchange rates and the Peppol access point. [DESIGN.md](DESIGN.md) has the architecture.

## Build and test

iOS 18 or later. MidgarKit and AICredits are local packages in the Midgar monorepo (`packages/`).

```
swift test --package-path Core/PayDayCore   # anywhere, no Xcode
scripts/setup.sh                            # once: .env.local, xcodegen, package resolve
scripts/ios-build.sh
scripts/ios-test.sh                         # core and hosted iOS tests
```

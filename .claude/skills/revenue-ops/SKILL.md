---
name: revenue-ops
description: Weekly Pay Day revenue ritual — pull metrics, append docs/metrics.csv, evaluate the 30/60/90 gates from the playbook, and output one decision. Use when asked to "run revenue ops", "check the numbers", or on a weekly cadence.
---

# Revenue ops ritual

Pay Day — EU e-invoicing app. App Store id `6779927672` (bundle `com.guitaripod.payday`). Run the whole ritual; end with a gate verdict, not raw numbers.

## 1. Pull metrics

Ratings + listing state (keyless, per storefront — at minimum us, de, fi; the audience is EU):

```bash
curl -s "https://itunes.apple.com/lookup?id=6779927672&country=de" | python3 -c "import json,sys; r=json.load(sys.stdin)['results'][0]; print(r['averageUserRating'], r['userRatingCount'], r['version'], r['price'])"
```

ASC sales/downloads (shared `~/Dev/operator/lib/asc.py`; key `DSS2FFU68G`, issuer in `~/.config/midgar/credentials.env`, vendor `93803823`):

- `GET /v1/salesReports?filter[frequency]=WEEKLY&filter[reportType]=SALES&filter[reportSubType]=SUMMARY&filter[vendorNumber]=93803823&filter[reportDate]=<YYYY-MM-DD of week>` — gzip TSV; SKU units separate app downloads from sub units (pro.annual/monthly/lifetime) and the four credit packs.
- ASC analytics report request (downloads/engagement): create an ONGOING request once via `POST /v1/analyticsReportRequests` for the app, then poll instances. Record the request id in docs/store-playbook.md §0.

RevenueCat (subscribers / MRR / trials — needs the project's v2 secret key `RC_SECRET_PAYDAY` in credentials.env once the RC project exists):

```bash
source ~/.config/midgar/credentials.env
curl -s "https://api.revenuecat.com/v2/projects/<RC_PROJECT>/metrics/overview" -H "Authorization: Bearer $RC_SECRET_PAYDAY"
```

mako credits ledger (Peppol-send + AI credit consumption, tenant `payday`, run from `~/Dev/rust/pixie`):

```bash
wrangler d1 execute openai-image-proxy --remote --command "SELECT COUNT(*) FROM credit_purchases WHERE tenant='payday' AND created_at >= datetime('now','-7 days')"
```

Review texts (reply-within-48h duty), per storefront:

```bash
curl -s "https://itunes.apple.com/de/rss/customerreviews/page=1/id=6779927672/sortby=mostrecent/json"
```

## 2. Record

Append one row to `docs/metrics.csv`:

```
date,us_ratings,us_avg,downloads_wk,trial_starts_wk,trials_converted_wk,sub_units_wk,credit_units_wk,peppol_sends_wk,proceeds_wk,notes
```

Commit it.

## 3. Evaluate gates (full table in docs/store-playbook.md §Gates)

- **Day 30**: ≥300 downloads AND ≥5 trial starts → hold course. <50 downloads = visibility problem: ASO iteration (subtitle/keywords/screenshot 1) before any product work. Pay Day is an ASO bet on the e-invoice/Peppol wedge — if the compliance keywords aren't pulling, re-cut the listing, don't touch the app.
- **Day 60**: trial→paid ≥35% → press: annual win-back offer + promote recurring invoices. <20% → lengthen trial to 14 days before touching prices. Also check credit-pack attach rate among Pro users (Peppol-send demand is the leading B2B value signal).
- **Day 90**: proceeds ≥€150/mo → start the experiment cadence (Adapty win-rate ladder: localization > trial structure > plan duration > price > cosmetics). Localization first — this is an EU app; German/French/Finnish/Dutch listings are the highest-win lever. Proceeds ≈ 0 with healthy funnel top → revisit positioning, not pricing. **Never ship features to fix a funnel.**

Pay-Day-specific watch: **Peppol-send allowance burn** (annual subs get a server-granted 60 sends/yr; monthly 5/mo). If the heavy-sender cohort's send rate implies allowance COGS > retained revenue, cut 60→40 (tunable via the mako promo grant, no metadata change).

## 4. Output

One short report: the new row, week-over-week deltas, which gate window is active, the single recommended action, and any unanswered reviews (draft replies, ask before posting). One decision per episode.

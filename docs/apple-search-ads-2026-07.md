# Pay Day — Apple Ads launch plan (2026-07-27)

The point of this spend is **not** ROAS. Pay Day currently gets almost no
impressions, and App Store rank is roughly metadata relevance × download
velocity × conversion × retention — with zero downloads, three of the four
factors are zero and organic impressions never start. Paid taps manufacture the
first velocity and conversion signal so the organic loop can begin. Judge it on
whether organic rank moves, not on payback in month one.

Run it **after** the localized metadata version is live, not before. Ads against
an English listing in a German storefront waste the tap.

## Account setup

Apple Ads **Advanced** (not Basic). Basic's automated targeting picks its own
keywords, which is the opposite of what is needed here — the entire thesis is
that a narrow, uncontested keyword cluster is winnable and the broad "invoice
maker" cluster is not. Advanced allows exact match.

New accounts get a **$100 credit**. Minimum spend is $5/day; there is no floor
that prices out a solo developer.

## Budget

Two storefronts, not five. Spreading €10/day across DE, FR, BE, NL and FI buys
statistically useless data in every one of them.

| Campaign | Storefront | Daily | 30 days |
|---|---|---:|---:|
| PayDay-DE-Compliance | Germany | €10 | €300 |
| PayDay-BE-Peppol | Belgium | €7 | €210 |
| | | | **€510** |

Less the $100 credit, roughly **€420 of real spend** to buy a decision.

Germany because it is the largest market with the nearest mandate (issuers over
€800k turnover from January 2027) and `e-rechnung` has a top-5 median of **one**
rating. Belgium because its B2B mandate has been in force since January 2026,
~500,000 businesses are already on Peppol, and `peppol` on the Belgian
storefront has a top-5 median of **zero** ratings.

## Campaign 1 — PayDay-DE-Compliance (Germany)

Ad group `exact-compliance`, exact match only, search match **off**:

```
e-rechnung
e-rechnung pflicht
e-rechnung pflicht 2027
erechnung
xrechnung
zugferd
factur-x
peppol
en 16931
e-rechnung erstellen
```

Deliberately excluded: `rechnung schreiben`, `rechnungsprogramm`, `rechnung app`.
Their top-5 carry 714–2,658 ratings; you would pay Lexware and Billdu prices for
taps that will not convert against a listing with no ratings.

Starting bid €0.60 CPT. These are low-volume, low-competition terms — start low,
raise only where impression share is capped by bid rather than by demand.

## Campaign 2 — PayDay-BE-Peppol (Belgium)

Ad group `exact-peppol`, exact match only:

```
peppol
e-factuur
e-facturatie
facturatie
factuur versturen
peppol factuur
```

Starting bid €0.50 CPT.

## What to check, and when

**Day 7 — is the funnel alive?**
Tap-through rate and conversion rate per keyword. Apple Ads reports
tap → install directly. If a keyword gets impressions but under ~10% tap-through,
the icon and first screenshot are the problem, not the keyword. If taps convert
under ~25%, the product page is the problem.

**Day 30 — did organic move?**
The only question that matters. Compare `operator/reports/aso-ranks.csv` against
the 2026-07-27 baseline:

| Term | Baseline | Target at day 30 |
|---|---|---|
| DE `e-rechnung` | unranked | ranked at all |
| DE `erechnung` | #37 | top 20 |
| DE `peppol` | #11 | top 5 |
| BE `peppol` | #24 | top 10 |
| BE `e-factuur` | unranked | ranked at all |

If paid installs are landing and organic rank has not moved at all after 30
days, the cold-start thesis is wrong for this app and the spend should stop —
that is a real possible outcome and worth naming in advance.

**Cost ceiling that makes this sane.** Pay Day Pro is €39.99/yr. Even at a poor
2% download-to-paid conversion, a €0.60 tap at a 30% conversion to install is
€2.00 per install and €100 per subscriber — bad on its own. It is only
justifiable as the purchase of a ranking signal, which is why it is capped at
€510 and has a hard stop at day 30. Do not scale it on ROAS logic.

## Not doing yet

Discovery / search-match campaigns, Today-tab placements, and the other
storefronts. All of them widen the funnel before it is known that the funnel
converts at all.

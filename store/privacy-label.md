# Pay Day App Privacy label

Answers for App Store Connect, App Privacy section. Apple does not expose this section through the API, so the founder enters it by hand. It matches `PayDay/PrivacyInfo.xcprivacy` and the policy at https://midgarcorp.cc/legal/pay-day/privacy/ (source: `web/midgarcorp/src/content/legal/pay-day/privacy.html`, last updated 23 October 2026). The Privacy Policy URL on the app info (`store/metadata/ios/app-info/*.json`) and the policy and terms links in the descriptions (`store/metadata/ios/version/1.1.5/*.json`) move from the `mako.midgarcorp.cc` addresses to the midgarcorp.cc ones with this release; `midgar listing` pushes them and, under the `metadata_edit` policy, only with the founder at a terminal. The old addresses redirect to the new ones, because mako answers them with a 301.

## Top-level answers

- Do you or your third-party partners collect data from this app: Yes.
- Data used to track you: none. No data type is used for tracking. The app asks for no tracking permission and `NSPrivacyTracking` is false with no tracking domains.
- Privacy policy URL: https://midgarcorp.cc/legal/pay-day/privacy/

## Data types collected

| Data type (Apple) | Linked to the user | Used to track | Purpose | What it is in Pay Day |
| --- | --- | --- | --- | --- |
| Identifiers, User ID | Yes | No | App Functionality | The anonymous account key mako issues for the credit balance and Pro status, and the random Midgar ID, kept in iCloud Keychain and shared with Midgar's other apps on the person's devices. The Midgar ID goes to `api.midgarcorp.cc` (the identity service), rides on mako calls so mako can link it to the account, and authorizes the portal's "Your Midgar" panel. RevenueCat also holds its own anonymous app user id. (New with this release.) |
| Contact Info, Name; Email Address; Physical Address | Yes | No | App Functionality | The buyer and seller details inside an invoice, only in the Peppol document the person sends, which travels with the account key to the worker and on to the access-point provider. |
| Financial Info, Other Financial Info | Yes | No | App Functionality | The amounts, VAT breakdown and bank details inside a sent Peppol document. |
| Photos or Videos | Yes | No | App Functionality | The photo picked for "draft line items from a photo", sent to mako and on to the AI provider after the person allows AI drafting. |
| User Content, Other User Content | Yes | No | App Functionality | The text of an AI description or reminder request, and the Peppol transmission record the worker keeps (invoice number, recipient address, result). |
| Purchases, Purchase History | Yes | No | App Functionality, Analytics, Developer's Advertising | The App Store transactions of Pay Day Pro and credit packs, verified by RevenueCat and recorded by mako; the install attribution is joined to whether the person subscribed. |
| Usage Data, Advertising Data | Yes | No | Analytics, Developer's Advertising | Apple Ads attribution (campaign, ad group, keyword, country) that mako stores against the anonymous account. No advertising identifier. |
| Usage Data, Product Interaction | No | No | Analytics | The anonymous More Apps card events (opened, shown, tapped) that the portal sends to `api.midgarcorp.cc/v1/signals` through MidgarKit's anonymous signals client, with no Midgar ID, device identifier or `Authorization` header. Reading "Your Midgar" sends no event. (New with this release.) |

Everything else is "Data Not Collected".

## Data types answered "not collected", and why

- Identifiers, Device ID: the app reads no advertising identifier and no vendor identifier. The first mako account is created with a DeviceCheck token that mako checks with Apple, which answers only yes or no; the app also keeps a random per-install id in the Keychain. This release ships without the App Attest entitlement, so MidgarKit creates no key id. If App Review reads either as a Device ID, the fallback is Device ID, App Functionality, linked.
- Contacts, Browsing History, Search History, Sensitive Info, Health & Fitness, Location: none.
- Diagnostics: the log (`Library/Logs/payday.log`) stays on the device and is never uploaded. MetricKit is not collected.
- Other Data: none.

## Check before the label is entered

- Every call to mako and to the Pay Day worker now goes through `api.midgarcorp.cc`; the legacy `mako.midgarcorp.cc` and `payday-worker.guitaripod.workers.dev` addresses are no longer used by this build, so the data collected is unchanged apart from the Midgar ID and the portal counts.
- Deleting the account in the app erases the mako account and the local data. It does not erase the Midgar ID, which Midgar's other apps share, and it does not erase the worker's Peppol transmission records (`peppol_sends`, keyed by the mako user id). The policy says so and gives the support address. A worker deletion route like Helia's would close that gap and is a founder call.
- The Midgar ID is not sent to RevenueCat and Pay Day's purchases still go through AICredits and RevenueCat only, so Purchase History is unchanged.

## Third-party SDK notes

- RevenueCat: processes purchase data on our behalf (Purchase History, User ID above).
- MidgarKit 4.3.1: `MidgarPortal` ships a manifest that declares Product Interaction for Analytics, not linked, matching the row above. `MidgarCore` (identity, HTTP, logging, signals) ships none and uses no required-reason API beyond the ones listed below. Anonymous signals send nothing else: MetricKit collection is not started.
- Cloudflare: hosts the gateway (`api.midgarcorp.cc`) and the services behind it, mako and the Pay Day worker, and may keep standard request logs (IP address) for a limited time; IP address is not a data type in the label.

## Required-reason APIs (in the manifest, not in the label)

- App: UserDefaults `CA92.1` (own settings), file timestamp `C617.1` (documents the person opens or exports).

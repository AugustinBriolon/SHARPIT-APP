# App Store submission — SharpIt 1.0

Where SharpIt stands before its first App Store review, and what only the account holder can do in
App Store Connect. Order follows the launch plan: legal → iOS compliance → payment and infra → beta.

## Done in code

| Item | Where |
|---|---|
| Privacy manifest, app (collected data, required-reason APIs: UserDefaults `CA92.1` + `1C8F.1` app group, file timestamp `C617.1`) | `SHARPIT-APP/PrivacyInfo.xcprivacy` |
| Privacy manifest, widget extension (UserDefaults through the app group, no collection) | `SharpItWidgets/PrivacyInfo.xcprivacy` |
| No iCloud entitlement: health data never leaves for iCloud | no `com.apple.developer.icloud-*` in any `.entitlements` |
| Apple Weather attribution (mark + legal link) | `Features/Today/WeatherToolbarChip.swift` |
| Export compliance: `ITSAppUsesNonExemptEncryption = NO` (HTTPS only) | build settings, app target |
| Usage strings: Health read/write, location, camera, microphone, speech, calendars, Bluetooth | build settings `INFOPLIST_KEY_NS*` |
| Account deletion in the app | Paramètres › Confidentialité |
| No Garmin in the app (guideline 5.2.2) | iOS ADR 0013 |
| SharpIt Pro: StoreKit 2 paywall (`SubscriptionStoreView`) with `appAccountToken`, restore, manage, auto-renew notice, Terms + Privacy links | `Features/Pro/ProView.swift` |
| Every transaction verified by the server (JWS against Apple's roots), tier derived server-side | SHARPIT ADR-044, `/api/v1/billing/apple/verify` |
| App Store Server Notifications V2 (renewal, expiry, grace, billing retry, refund, revoke) | `/api/billing/apple/notifications` |
| French + English: String Catalog (`SharpItShared/Localizable.xcstrings`, `SHARPIT-APP/InfoPlist.xcstrings`), Paramètres › Langue, English for any other device language; server copy, pushes and coach follow | iOS ADR 0019, SHARPIT ADR-096 |
| Local StoreKit testing: `Config/SharpitPro.storekit`, preselected in the shared scheme; a dev API accepts its `Xcode` transactions, a production build never does | `ProProductsTests`, `apple-verifier.test.ts` |

## Subscription metadata (proposal)

Mirrors `Config/SharpitPro.storekit`. The product ids are fixed in code (`SharpitProProduct`).

| Field | Monthly | Yearly |
|---|---|---|
| Subscription group | SharpIt Pro | SharpIt Pro |
| Product id | `app.sharpit.ios.pro.monthly` | `app.sharpit.ios.pro.yearly` |
| Reference name | SharpIt Pro Monthly | SharpIt Pro Yearly |
| Duration | 1 month | 1 year |
| Price (France, base) | 9,99 € | 79,99 € (≈ 33 % off 12 months) |
| Display name (fr) | SharpIt Pro — mensuel | SharpIt Pro — annuel |
| Description (fr) | Bilan hebdomadaire, analyse de séance et lecture coach du journal. | same |
| Display name (en) | SharpIt Pro — Monthly | SharpIt Pro — Yearly |
| Description (en) | Weekly summary, session analysis and the coach's reading of your journal. | same |
| Group display name (en) | SharpIt Pro | |
| Group display name (fr) | SharpIt Pro | |
| Family Sharing | off | off |
| Introductory offer | none for 1.0 (a free week can be added later; mirror it in the `.storekit`) | |

Review screenshot of the paywall: Paramètres › SharpIt Pro on a free account.

**Check before submitting:** the perk « Envoi vers la montre » is listed as Pro by the web
(`pro-perks.ts`) and shows in the iOS paywall, but the iOS app has no Garmin push (ADR 0013).
Mark it `planned` or hide it on iOS so the paywall only sells what the app does (guideline 2.3.1).

## Localization (App Store Connect)

The app ships in French and English (iOS ADR 0019). App Store Connect lists a language for each
localization added to the version; the primary language decides the fallback in every other
storefront.

- **Primary language: English (U.K. or U.S.)**, so storefronts outside France read English, and add
  **French** as a second localization. Keeping French primary would show French metadata worldwide.
- **App name**: SharpIt (both). **Subtitle** (30 chars): fr « Ton coach triathlon et endurance »,
  en “Your triathlon & endurance coach”.
- **Promotional text** (en): “A coach that reads your night, your load and your plan every morning,
  and tells you what today's session should be.”
- **Description** (en), first lines: “SharpIt reads your sleep, heart rate, HRV and training from your
  watch through Apple Health, and turns them into one decision each morning: train, go easy or rest.
  Your plan adapts when life gets in the way, and the coach answers questions about your own data.”
  Then the same feature list as the French description, translated.
- **Keywords** (en, 100 chars): `triathlon,training plan,endurance,coach,HRV,recovery,running,cycling,swim,ironman`
- **What's New** (en): “First release.”
- **Screenshots**: one set per language. Shoot English with Paramètres › Langue › English (or a
  simulator in English), same screens as listed below.
- **Subscriptions**: add the English display names and descriptions above to both products and the
  group, or English storefronts show the French ones.
- **Privacy policy / Terms**: `sharpit.app/privacy` and the terms are French only. Apple accepts
  that, but an English version (or a translated summary) is worth adding before marketing abroad.
- **Review notes**: add “The app follows the device language (French or English); Settings ›
  Langue / Language switches it.”

## App Privacy answers (App Store Connect › App Privacy)

Matches the manifest. Tracking: **No**. For every type below: linked to the user, not used for
tracking, purpose App Functionality.

- Health & Fitness: Health, Fitness
- Location: Precise Location (weather where the athlete trains)
- Identifiers: User ID
- Contact Info: Email Address, Name
- Purchases: Purchase History
- User Content: Other User Content (journal, coach questions, food log)
- Diagnostics: Crash Data (Sentry, no personal data)

## Review notes (App Review Information)

Update `docs/beta-testflight.md` « Beta App Review notes » with the demo account and add:

> Compte de démonstration : <email> / <mot de passe> — athlète « Athlète Démo », plan et
> historique déjà remplis. SharpIt Pro se teste depuis Paramètres › SharpIt Pro avec un compte
> Sandbox ; l'achat est vérifié par notre serveur (App Store Server API) puis le palier passe Pro.
> Apple Santé est optionnel et en lecture/écriture limitée (journal alimentaire, poids). Les données
> de santé ne sont jamais synchronisées sur iCloud.

## Screenshots

`TARGETED_DEVICE_FAMILY = 1,2`: the app ships on iPad too, so App Store Connect requires both sets.
Either provide them or switch the target to iPhone only before the first submission (decision).

- iPhone 6.9" (1320 × 2868), 3 to 10 shots: Aujourd'hui (verdict du matin), Plan de la semaine,
  « Rattraper ma semaine », Course (projection), Coach, Journal alimentaire, SharpIt Pro.
- iPad 13" (2064 × 2752), same screens — only if iPad stays supported.

## Only the account holder can do this — in order

1. **Agreements, Tax and Banking**: sign the Paid Apps agreement, enter bank account and tax forms.
   Products stay « Missing Metadata » and cannot be bought until this is active.
2. **Subscriptions**: create the group « SharpIt Pro » and both products with the ids, durations,
   prices and localizations above, plus a review screenshot of the paywall.
3. **App Store Server API key**: Users and Access › Integrations › In-App Purchase, generate a key
   (only needed if we later call the App Store Server API; verification of JWS needs no key).
4. **Vercel (production)**: set `APPLE_APP_APPLE_ID` to the app's numeric Apple ID (App
   Information › Apple ID). Without it, every production purchase is refused.
5. **Server Notifications V2**: check the Production and Sandbox URLs are
   `https://api.sharpit.app/api/billing/apple/notifications`, then « Request a Test Notification ».
6. **Demo account**: create a sign-in for the demo athlete and put it in the review notes.
7. **App Privacy**: answer as listed above. **Age rating**: complete the questionnaire.
8. **Version page**: primary language English plus a French localization (see Localization),
   screenshots per language, description, keywords, support URL, privacy policy URL
   (`https://sharpit.app/privacy`), subscriptions attached to version 1.0.
   Before an English build reaches testers, apply the `20261019120000_athlete_locale` migration in
   production (the server stores the athlete's language there).
9. **Sandbox check**: on TestFlight, buy with a Sandbox account, confirm Paramètres › SharpIt Pro
   shows Pro and that the subscription row exists on the server.
10. **Upload the build** from Xcode Organizer (CLI export needs an Apple account in Xcode).
11. **Submit for Review** with the subscriptions included in the same submission.

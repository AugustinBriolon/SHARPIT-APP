# Corps tab, Paramètres and SharpIt Pro — iOS design and web contract

Status: proposed — 2026-09-24. Supersedes nothing; the Moi hub described in `CLAUDE.md` is what
this replaces.

## Why

Moi mixes three different things: what SHARPIT knows of the athlete's body (Corps, Seuils &
repères, Profil), what the athlete tunes (density, sources, privacy) and what belongs to other
tabs (Objectifs, Mémoire du coach). The body is the product's evidence and deserves a tab; the
settings deserve to be one tap away but out of the tab bar; goals and memory belong beside the
plan and the coach that read them.

## Information architecture

| Before (Moi tab) | After |
| --- | --- |
| Corps, Seuils & repères | **Corps** tab (replaces Moi in the tab bar) |
| Profil (height, birth date) | Paramètres → Compte |
| Objectifs | Plan → « … » menu → Objectifs |
| Mémoire du coach (context, trips) | Coach → toolbar « Mémoire » → drawer |
| Densité de lecture, Sports & équipement, Connexions, Confidentialité | Paramètres |
| — | Paramètres → SharpIt Pro, Apparence, Notifications, Synchronisation iCloud |

Tab bar: Résumé · Plan · Coach · Activité · **Corps**.

### Résumé header

- Navigation bar, trailing: the athlete's avatar — Clerk `imageUrl`, else initials on a neutral
  disc — opening **Paramètres** as a sheet (Apple's Fitness / App Store pattern).
- Large title: the date, larger than today's inline title, in the same place.
- Under the title, one row of glass controls: activity mode (today's leading chip), Journal,
  weather. They leave the navigation bar, which keeps only the avatar.

UX adjustment over the brief: Paramètres opens as a sheet with its own navigation stack rather
than a push, so closing it always lands back on Résumé, and the same sheet can be opened from
Corps' toolbar avatar too.

### Corps tab

Causal column, as every screen:

1. **Hero** — weight and its 7-day change (or, before any weigh-in, the invitation to connect a
   scale); biological age slot, hidden until the web serves one.
2. **Récupération** — HRV reference (Garmin baseline band + 7-day mean), resting HR reference
   (7/30-day mean), VO₂max run / bike.
3. **Composition** — body fat %, lean mass (kg), muscle %, water %, bone mass, BMI, visceral fat,
   basal metabolism; Withings body / vascular age when the scale reports them.
4. **Seuils** — FTP, max HR, LTHR, threshold pace, CSS (read here; edited in a form sheet from
   the section header, replacing Seuils & repères).
5. Confidence / source line (which scale, which watch, last sync).

Every metric is a tile (`sharpitPressable`, chevron, semantic tone on the delta) opening a
**metric drawer**: a Swift Charts line over 30 d / 90 d / 1 an / Tout, the baseline band where
one exists, the latest value, min/max and the source. Tiles for metrics with no data are hidden,
not shown empty; the essential density shows fewer tiles than the expert one (ADR 0006).

### Paramètres

1. **SharpIt Pro** — current tier, what Free has, what Pro adds (perks served by the web),
   subscribe / manage.
2. **Général** — Compte (first name, last name, sex, height, birth date, age derived, email
   read-only, photo), Apparence (Système / Clair / Sombre), Notifications, Sources de données
   (today's Connexions), Synchronisation iCloud (account status, last export / import, last
   error).
3. **Entraînement** — Sports & équipement, Densité de lecture.
4. **Confidentialité & conditions.**
5. Footer: version, sign out.

### Coach

Toolbar button « Mémoire » (next to history) opening a large drawer: free context (the
profile's `context`), active and upcoming trips (existing `TravelMemorySheet`), memory items.
Reuses `CoachMemoryStore`.

### Plan

« … » menu gains **Objectifs** (existing `GoalsView` in a sheet) above the plan operations.

## SharpIt Pro — how billing works on iOS

- Apple requires digital subscriptions sold inside an iOS app to go through **In-App Purchase**
  (App Review guideline 3.1.1). Stripe can sell the same Pro on the web; the two must meet in
  one server-side entitlement — `AthleteProfile.tier` through `hasProAccess`, as today.
- App Store Connect: a subscription group « SharpIt Pro » with monthly and yearly products,
  optional free trial. A StoreKit configuration file in the repo lets the simulator buy without
  App Store Connect.
- App: StoreKit 2. `SubscriptionStoreView` (native paywall) inside the Pro page; every purchase
  carries an `appAccountToken` (a UUID the web issues per athlete) so Apple's notifications can
  be tied to the account; `Transaction.updates` is observed from launch; after a purchase the app
  sends the signed transaction to the web and re-reads the tier.
- Web: verifies the JWS with Apple's App Store Server Library, stores the subscription, sets
  `tier`, and listens to **App Store Server Notifications V2** (renewal, expiry, refund, grace
  period) — the app is never the authority on the tier.
- Alternative: RevenueCat does verification, notifications and web ↔ app unification as a
  service (free under 2.5 k$ MTR). Simpler, one more vendor. Decision left to the owner.

## Biological age

Web-owned computation; the app only renders it. Candidate method, to be documented in a web ADR:
a fitness-age core from VO₂max (Nes et al., HUNT Fitness Study, 2013), adjusted by resting HR,
HRV relative to age norms and body fat; the Withings `bodyAge` / `vascularAgeYears` shown as
separate, attributed readings, never blended in silently. Copy must stay inside the health
disclaimer (an estimate for training, not a diagnosis).

## Web contract requested

All under `/api/v1`, Clerk Bearer auth, re-exported handlers per ADR-040.

1. `GET /api/v1/body/overview` — every Corps metric in one read:
   `{ metrics: [{ key, value, unit, previous?, deltaWindowDays?, baseline?: { low, high } | null,
   measuredAt, source }], biologicalAge: null | { years, chronologicalYears, method, confidence,
   inputs: [key], computedAt } }`. Keys: `weight`, `bodyFatPct`, `leanMassKg`, `musclePct`,
   `waterPct`, `boneKg`, `bmi`, `visceralFat`, `bmr`, `bodyAgeScale`, `vascularAge`, `hrv`,
   `restingHr`, `vo2maxRun`, `vo2maxBike`, `ftp`, `maxHr`, `lthr`, `runThresholdPace`,
   `swimCss`.
2. `GET /api/v1/body/series?metric=<key>&range=30d|90d|1y|all` —
   `{ metric, unit, points: [{ date, value }], baseline?: [{ date, low, high }] }`.
3. `AthleteProfile.sex` (`female` | `male` | `other` | null) in the PATCH validator and the GET
   payload — biological age and HR norms need it. First name, last name, email and photo stay in
   Clerk (the app edits them through the Clerk SDK).
4. `AthleteProfile.notificationPrefs` (Json, versioned): `{ version: 1, morningVerdict: bool,
   morningTime: "HH:mm" | null, weeklyReview: bool, sessionReminder: bool, syncAlerts: bool }`,
   honoured by the push crons.
5. `GET /api/v1/pro` — `{ tier, perks: [{ id, title, description, status: pro|included|planned }],
   subscription: null | { status, source: apple|stripe|manual, renewsAt, expiresAt,
   willRenew } }` — perks from `pro-perks.ts`, so the app never duplicates the copy.
6. Billing: `POST /api/v1/billing/apple/app-account-token`, `POST /api/v1/billing/apple/verify`
   (signed transaction → subscription + tier), `POST /api/billing/apple/notifications` (App Store
   Server Notifications V2 webhook), a `Subscription` table, and the tier derived from it.
7. `POST /api/v1/garmin/sync` re-exporting `/api/garmin/sync` (removes the last native debt
   besides the coach chat).

## iOS execution plan

- **Lot 1 — Navigation** (no web dependency): Corps tab replacing Moi (first version built from
  today's `BodyView`, `ThresholdsView` data and `/api/v1/recovery` history); Paramètres sheet with
  the new grouping; avatar button; Résumé header rework; Objectifs in Plan's menu; Mémoire drawer
  in Coach.
- **Lot 2 — Paramètres pages** (no web dependency except `sex`): Compte (Clerk names, photo,
  email; profile height and birth date), Apparence (device-local `preferredColorScheme`),
  Synchronisation iCloud (`CKContainer.accountStatus`,
  `NSPersistentCloudKitContainer.eventChangedNotification` recorded per event type), Sources de
  données (Connexions).
- **Lot 3 — Corps on the web contract**: overview + series endpoints, metric drawer with Swift
  Charts and ranges, density-aware tiles, biological-age slot.
- **Lot 4 — Notifications**: `notificationPrefs` page, APNs authorisation state, deep link to
  iOS Settings when denied.
- **Lot 5 — SharpIt Pro**: StoreKit configuration file, Pro page from `/api/v1/pro`,
  `SubscriptionStoreView`, transaction observer, verify round-trip, manage subscription
  (`manageSubscriptionsSheet`), restore.

Each lot lands with tests on its stores and pure mappings, and updates `CLAUDE.md`.

## Open decisions

- StoreKit direct vs RevenueCat; prices; trial length; which features are Pro (the web's
  `pro-perks.ts` is the list to start from).
- Tab name: « Corps » (proposed) or « Biologie ».
- Whether Apparence syncs to the web or stays per device (proposed: per device).

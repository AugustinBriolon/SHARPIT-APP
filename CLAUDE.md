# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Native iPhone client for SHARPIT (Athlete State Intelligence). The web app lives in the
sibling repository `../SHARPIT` (Next.js) and owns the domain, the database, and the
design system. This repo renders that system natively — it does not redefine it.

Language: all code, comments, docs, commits and ADRs are written in English. User-facing
UI copy is French.

## Build, run, test

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' build
```

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

Run a single test — Swift Testing, so filter on the suite or function name:

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  test -only-testing:SHARPIT-APPTests/TodayStoreTests
```

Requirements: Xcode 27 / Swift 6 language mode, iOS 27 simulator (Liquid Glass), Clerk
Native API enabled with the same publishable key as the web app.

### Where the data comes from

The app talks to the web app over HTTP and never to the database directly. Domain logic,
the Clerk session and athlete scoping all live server-side, so a client holding database
credentials would bypass every one of them and would have to re-implement the Core.

The origin belongs to the build, not to Xcode: `Config/Debug.xcconfig` and
`Config/Release.xcconfig` set `SHARPIT_API_ORIGIN`, `Config/Info-Extra.plist` copies it into
the Info.plist as `SharpitAPIOrigin`, and `APIConfiguration.baseURL` reads it. A
`SHARPIT_API_ORIGIN` environment variable still overrides it, but only when Xcode launches
the app — a home-screen or TestFlight launch never sees it, which is why it cannot be the
only mechanism. In an xcconfig `//` starts a comment, so write `https:/$()/host`.

- **Local full stack** — `docker compose up -d` then `yarn dev` in `../SHARPIT`. Debug
  default (`http://127.0.0.1:3000`).
- **Deployed instance** — Release points at `https://sharpit.app`. To run a Debug
  build against it, put `SHARPIT_API_ORIGIN = https:/$()/sharpit.app` in
  `Config/Local.xcconfig` (gitignored), or set the variable in the scheme for the
  simulator. Real data, no Docker, no local Next.
- **No server at all** — `FixtureTodayClient` serves the bundled JSON for pure UI work.

Clerk is still the development instance (`pk_test_…`), the same one the deployed web app
uses, so the app's token is accepted there. A production Clerk instance needs a `pk_live_…`
key and is a separate step.

### Signing

Simulator builds use **Sign to Run Locally** (`CODE_SIGN_IDENTITY=-`,
`CODE_SIGNING_ALLOWED=YES`) because Clerk needs the Keychain — a fully unsigned app crashes
at launch with OSStatus `-34018`. The identity is conditional on the SDK
(`CODE_SIGN_IDENTITY[sdk=iphonesimulator*]`), so a device build signs with `Apple Development`
instead.

The app target supports `iphoneos` as well as the simulator. The team is not in the project:
each machine sets `DEVELOPMENT_TEAM` in the gitignored `Config/Local.xcconfig`, which also
holds the API origin override.

WeatherKit, HealthKit and CloudKit are all entitled in `SharpIt.entitlements` and all need a
paid team. Xcode reissues the managed profile when an entitlement is added, so a capability that
silently does nothing — the weather chip reading "Météo indisponible" was exactly this — usually
means the entitlement is missing rather than the code being wrong. Associated Domains is still
not entitled.

## Architecture

The test target imports the module as `Sharpit` (`@testable import Sharpit`), not
`SHARPIT-APP`.

**Entry / auth.** `SharpitApp` configures Clerk and the SwiftData `ModelContainer`, then
wraps `RootView` in `AuthGate`. Every network call takes a Bearer token produced by
`clerk.auth.getToken()`; views receive it as an injected `tokenProvider` closure rather
than reaching for Clerk themselves.

**Onboarding.** `OnboardingGate` sits between `AuthGate` and `RootView`: a new account answers
the web's first-login wizard before it sees the tabs — Sports → Équipement → Disponibilités →
Intention → Sources, the web's `wizard-steps.ts` order. The server decides who owes it
(`onboardingCompletedAt` present and `null` on `/api/v1/athlete-profile`, as the web's gate reads
the row); the phone only remembers a "done" per Clerk user, so a finished athlete never waits on
a profile read, and a read that fails lets the athlete in without remembering anything. Each step
is written as the athlete leaves it (practiced sports, equipment, `trainingAvailability`, a first
goal through `/api/v1/goals`), and only `/api/onboarding/complete` finishes the wizard. Sources
mirrors Connexions: Garmin is connected on the web, Apple Health is switched on here — the web's
per-class source routing is not modelled.

**Shell.** `RootView` is a five-tab `TabView` (Résumé / Plan / Coach / Activité / Moi).
`ShellDestination` describes the tabs that are not built yet and feeds
`InstrumentShellView` placeholders. Today, Plan and Activité are real screens.

**Feature shape.** A feature is a `@Observable` store plus a view that only composes
design-system components: `TodayStore` owns a `phase` enum (loading / loaded / empty /
failed / unauthorized) and `TodayView` switches on it. Feature views must not invent
typography, colors or spacing — that belongs to `DesignSystem/`.

**Networking.** Protocol per resource (`TodayServing`, …) so tests inject stubs;
`FixtureTodayClient` serves bundled JSON from `SHARPIT-APPTests/Fixtures`. Wire types live
in `V1Today.swift` / `V1Activities.swift` / `V1PlannedSessions.swift` and mirror the web
API payloads.

Every client calls the versioned `/api/v1/*` contracts (SHARPIT ADR-040: each one re-exports
the `/api` handler, same Clerk authz). Three routes have no `/api/v1` twin yet and are called
web-internal: `/api/coach/chat` (deferred on the web), `/api/onboarding/complete`
(`OnboardingClient`) and `/api/privacy/consent` (`PrivacyConsentClient`). Treat those as known
debt, not as a pattern to copy — move each one the day the web publishes its `/api/v1` twin.

**Coach history.** The server keeps the conversations and the client saves the whole thread
after each answer, as the web does. A turn opened from history keeps its stored JSON
(`CoachMessage.stored`) and is sent back as it came, because the web writes parts the app
does not model — tool calls — and a save from the phone must not strip them.

**Journal.** `JournalView` asks for the day signals the athlete turned on, and
`JournalPrefsDrawer` chooses them. Preferences are kept as the raw JSON the server sent
(`JournalPrefs.raw`): the web stores keys the app does not model — diet flags, nutrition
panel, thresholds — and the server rebuilds its enable map from defaults for every key a
payload omits, so sending back only what the app renders would silently reset the rest. The
catalogue in `JournalTrackables.swift` therefore covers the signals the app can render, never
all of the web's.

Sections follow *when* a signal happened, not what kind of thing it is: Journée (the three
metrics), Checklist auto, Nuit dernière, Signaux du jour. `JournalDayWindow` is its own axis
beside `JournalCategory`, which still drives the drawer's filters — the web separates them
too, so one cannot be derived from the other. The automatic checklist is read from
`/api/journal/day-signals` and never recomputed: the thresholds, the sports that count as
cardio and the minutes summed per activity all live in the web's `journal-auto-checklist.ts`,
and a second implementation would diverge the first time a threshold moved. Its lines are
read-only, so they carry no toggle and no chevron, and the route is called only when the
athlete enabled one.

**Activity status.** The mode chip in Today's toolbar writes `/api/activity-status` on every
pick — no explicit save, as on the web. A deadline that has passed is resolved back to
`active` server-side on read, so the app never expires one itself. Trips are not modelled:
the app carries `travelId` back unchanged rather than inventing one.

**Day drill-downs.** Sleep and Recovery open from the Today gauges. Both are a
`DayResourceStore` inside `DayDetailScaffold`, which pins the day picker
(`DayDetailDatePicker`, built on the Plan's `SharpitWeekStrip`) above the content; a new
day's drill-down is a v1 resource plus a sections view, not a new store.

**Native never calls `/api/presentation/*`** — see SHARPIT ADR-040. The web presentation
layer is web-only; the app maps domain payloads itself.

**Persistence.** SwiftData, two models keyed by `trainingDayId`: `TodayDaySnapshot` holds the raw
encoded `V1TodayResponse`, `JournalDaySnapshot` holds a day's entry, preferences and derived
checklist. One repository each, and they are the only accessors, so both screens paint offline
before the network answers.

The cache is never the truth — the server is. A write goes to `/api`, the cache is written from
the server's echo and never merged with it. It replicates through the athlete's **private**
CloudKit database (`docs/adr/0007`), which costs the schema a `#Unique`: CloudKit refuses one, so
each repository resolves a day by fetching every row for it sorted by `fetchedAt` descending,
keeping the newest and deleting the rest. Every attribute has a default and every payload is
optional for the same reason. An in-memory container skips CloudKit, so a test never reaches the
network.

**Freshness.** The app starts provider pulls itself (`ProviderSyncStore`, `/api/v1/sync`)
on launch, foreground and pull-to-refresh, and can send Apple Health day summaries
(`AppleHealthSource`, `/api/v1/health-samples`) when the athlete switches it on in Moi.
Apple Health only fills gaps; Garmin stays the reference (`docs/adr/0005`, SHARPIT
ADR-043). HealthKit is read-only and entitled in `SharpIt.entitlements`.

**Moi.** A grouped hub of the web's Réglages surfaces (`SharpitHubGroup`): Modèle, Compte,
Préférences, Données, À propos. Profil and Seuils & repères edit the profile through
`AthleteProfilePatch`, which carries only the fields the athlete changed — an absent key means
"leave it" and an explicit `null` means "clear it", a distinction a `Codable` struct of
optionals cannot express. The web's validator records why: a PATCH that materialised the
fields it had not been given once wiped an athlete's thresholds on a one-field save. Corps is
read-only; a weigh-in is written by a scale.

**Reading density.** `displayMode` (`essential` / `expert`) is read once into a
`DisplayModeStore` in the environment; a surface asks `\.isExpertReading` rather than the
profile (`docs/adr/0006`). It governs what is shown and how it is named, never what is
measured — session load appears in both readings, as « charge 78 » or « 78 TSS », mirroring
the web's `formatTrainingLoad`. It is a reading preference, not an access tier: `tier`
(FREE / PRO) gates features, the density gates nothing.

**Weather** comes from WeatherKit + Core Location (`LocationWeatherService`), never from
the API.

## Design system

`SHARPIT-APP/DesignSystem/` is the only place that defines tokens and shared components.

The source of truth is the web design system, not this repo:

- Law: `../SHARPIT/design.md` and `../SHARPIT/docs/design/DESIGN_LANGUAGE.md`
- Values: `../SHARPIT/src/lib/brand/brand-tokens.ts` and `../SHARPIT/src/app/globals.css`

Genre is **instrument-editorial**: a precision readout, not a fitness dashboard. That
implies color reserved for semantic state and no decorative gradients or washes. Apple
chrome (tab bar, navigation, Liquid Glass) stays system; brand meaning lives in the content.

Elevation is where the app departs from the web (`docs/adr/0002`): surfaces have no
hairline border; on light they lift with a soft neutral shadow (`sharpitShadow`), on dark by
luminosity only. Every sheet uses `.sharpitSheet()` so none falls back to system black, and
no screen uses `Color(uiColor: .systemBackground)`.

Color and affordance (`docs/adr/0004`): numbers take semantic tones from
`SessionFeedbackTone`, anything that opens something is a raised tile with a chevron and
`.buttonStyle(.sharpitPressable)`, and `CoachDiscussButton` is a tinted pill placed with
the title of what it discusses — never at the bottom of a screen. Session feeling is written in the web's words (`SessionFeeling.storedValue`).

Motion: `SharpitMotion.selection` for controls under the finger, `reveal` for content
arriving; `staggerDelay(index:)` is capped, so use it instead of hard-coded delays.

Screen structure follows the web causal column: state → evidence → recommendation →
projection → limit → confidence.

Forbidden, on both platforms: streak counters, radial gauges dominating a hero, sparkle /
chatbot chrome, colored glow shadows, invented metrics, motivational micro-copy.

## Related specs

`docs/superpowers/specs/` holds the design and parity specs. Read the most recent one on a
subject before changing that subject — earlier specs are superseded, not merged.

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
- **Deployed instance** — Release points at `https://sharpit.vercel.app`. To run a Debug
  build against it, put `SHARPIT_API_ORIGIN = https:/$()/sharpit.vercel.app` in
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
holds the API origin override. Associated Domains and WeatherKit still need a paid team.

## Architecture

The test target imports the module as `Sharpit` (`@testable import Sharpit`), not
`SHARPIT-APP`.

**Entry / auth.** `SharpitApp` configures Clerk and the SwiftData `ModelContainer`, then
wraps `RootView` in `AuthGate`. Every network call takes a Bearer token produced by
`clerk.auth.getToken()`; views receive it as an injected `tokenProvider` closure rather
than reaching for Clerk themselves.

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

Only `/api/v1/today` is a real versioned contract today. `ActivityClient`,
`PlannedSessionClient`, `CoachChatClient`, `CoachConversationClient`, `ActivityStatusClient`
and `JournalClient` call web-internal routes (`/api/activities`, `/api/planned-sessions`
including `…/:id/link`, `/api/coach/chat`, `/api/coach/conversations`, `/api/activity-status`,
`/api/day-journal`, `/api/journal-prefs`); treat that as known debt, not as a pattern to copy.

**Coach history.** The server keeps the conversations and the client saves the whole thread
after each answer, as the web does. A turn opened from history keeps its stored JSON
(`CoachMessage.stored`) and is sent back as it came, because the web writes parts the app
does not model — tool calls — and a save from the phone must not strip them.

**Journal.** `JournalView` asks for the day signals the athlete turned on, and
`JournalPrefsDrawer` chooses them. Preferences are kept as the raw JSON the server sent
(`JournalPrefs.raw`): the web stores keys the app does not model — automatic items fed by
device sync, diet flags, thresholds — and the server rebuilds its enable map from defaults
for every key a payload omits, so sending back only what the app renders would silently
reset the rest. The catalogue in `JournalTrackables.swift` therefore covers the signals the
app can render, never all of the web's.

**Activity status.** The mode chip in Today's toolbar writes `/api/activity-status` on every
pick — no explicit save, as on the web. A deadline that has passed is resolved back to
`active` server-side on read, so the app never expires one itself. Trips are not modelled:
the app carries `travelId` back unchanged rather than inventing one.

**Native never calls `/api/presentation/*`** — see SHARPIT ADR-040. The web presentation
layer is web-only; the app maps domain payloads itself.

**Persistence.** SwiftData, one model: `TodayDaySnapshot` keyed by `trainingDayId`, storing
the raw encoded `V1TodayResponse`. `TodaySnapshotRepository` is the only accessor, so Today
renders instantly offline before the network answers.

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

Color and affordance (`docs/adr/0003`): numbers take semantic tones from
`SessionFeedbackTone`, anything that opens something is a raised tile with a chevron and
`.buttonStyle(.sharpitPressable)`, and `CoachDiscussButton` is the one filled call to
action. Session feeling is written in the web's words (`SessionFeeling.storedValue`).

Motion: `SharpitMotion.selection` for controls under the finger, `reveal` for content
arriving; `staggerDelay(index:)` is capped, so use it instead of hard-coded delays.

Screen structure follows the web causal column: state → evidence → recommendation →
projection → limit → confidence.

Forbidden, on both platforms: streak counters, radial gauges dominating a hero, sparkle /
chatbot chrome, colored glow shadows, invented metrics, motivational micro-copy.

## Related specs

`docs/superpowers/specs/` holds the design and parity specs. Read the most recent one on a
subject before changing that subject — earlier specs are superseded, not merged.

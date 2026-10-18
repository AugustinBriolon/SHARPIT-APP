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
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -parallel-testing-enabled NO test
```

Run a single test — Swift Testing, so filter on the suite or function name:

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -parallel-testing-enabled NO \
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

- **Local full stack** — `docker compose up -d` then `yarn dev` in `../SHARPIT-WEBAPP`: the API
  (`apps/api`, `http://127.0.0.1:3001`, Debug's `SHARPIT_API_ORIGIN`) and the web pages (`apps/web`,
  `http://127.0.0.1:3000`, Debug's `SHARPIT_WEB_ORIGIN`).
- **Deployed instance** — Release points at `https://api.sharpit.app` (JSON + Bearer only)
  and opens web pages on `https://sharpit.app` (`SHARPIT_WEB_ORIGIN`). To run a Debug build
  against it, put `SHARPIT_API_ORIGIN = https:/$()/api.sharpit.app` and
  `SHARPIT_WEB_ORIGIN = https:/$()/sharpit.app` in `Config/Local.xcconfig` (gitignored), or set
  the API variable in the scheme for the simulator. Real data, no Docker, no local Next.
- **No server at all** — `FixtureTodayClient` serves the bundled JSON for pure UI work.

Clerk is the production instance (`pk_live_…`, Frontend API `clerk.sharpit.app`,
`APIConfiguration.publishableKey`), the same one the deployed web app uses, so the app's token
is accepted there.

### Signing

Simulator builds use **Sign to Run Locally** (`CODE_SIGN_IDENTITY=-`,
`CODE_SIGNING_ALLOWED=YES`) because Clerk needs the Keychain — a fully unsigned app crashes
at launch with OSStatus `-34018`. The identity is conditional on the SDK
(`CODE_SIGN_IDENTITY[sdk=iphonesimulator*]`), so a device build signs with `Apple Development`
instead.

The app target supports `iphoneos` as well as the simulator. The team is not in the project:
each machine sets `DEVELOPMENT_TEAM` in the gitignored `Config/Local.xcconfig`, which also
holds the API origin override.

WeatherKit, HealthKit and Push Notifications (`aps-environment`) are all entitled in
`SharpIt.entitlements` and all need a paid team. `Config/Info-Extra.plist` declares the
`remote-notification` background mode: the morning-verdict APNs push needs it. No iCloud: the
cache holds health-derived data (`docs/adr/0009`). Automatic signing stamps `aps-environment` as `production` on an archive, so
the file keeps `development`. WeatherKit also has to be ticked on the App ID in the developer
portal, under both Capabilities and App Services; until it is, weatherd logs
`WDSJWTAuthenticatorServiceListener.Errors Code=2` and the chip reads "Météo indisponible". Xcode reissues the managed profile when an entitlement is added, so a capability that
silently does nothing — the weather chip reading "Météo indisponible" was exactly this — usually
means the entitlement is missing rather than the code being wrong.

## Architecture

The test target imports the module as `Sharpit` (`@testable import Sharpit`), not
`SHARPIT-APP`.

**Entry / auth.** `SharpitApp` configures Clerk and the SwiftData `ModelContainer`, then
wraps `RootView` in `AuthGate`. Every network call takes a Bearer token produced by
`clerk.auth.getToken()`; views receive it as an injected `tokenProvider` closure rather
than reaching for Clerk themselves. The sign-in drawer puts Apple first, as Apple's own
`ASAuthorizationAppleIDButton` (`SharpitAppleSignInButton`: black on light, white on dark), with
Clerk's `signInWithApple()` running the native authorization; Google sits under it, white in
both appearances (Google's light theme) with the official « G » (`SharpitGoogleSignInButton`),
same shape and height.

Feature-specific behaviour (screens, flows, the web routes they mirror) lives in a `CLAUDE.md`
inside each feature directory (`SHARPIT-APP/Features/<Feature>/CLAUDE.md`, `SharpItWidgets/CLAUDE.md`),
loaded when working there. This file keeps the rules that hold everywhere.

**Feature shape.** A feature is a `@Observable` store plus a view that only composes
design-system components: `TodayStore` owns a `phase` enum (loading / loaded / empty /
failed / unauthorized) and `TodayView` switches on it. Feature views must not invent
typography, colors or spacing — that belongs to `DesignSystem/`.

**Networking.** Protocol per resource (`TodayServing`, …) so tests inject stubs;
`FixtureTodayClient` serves bundled JSON from `SHARPIT-APPTests/Fixtures`. Wire types live
in `V1Today.swift` / `V1Activities.swift` / `V1PlannedSessions.swift` and mirror the web
API payloads.

Every client calls the versioned `/api/v1/*` contracts (SHARPIT ADR-040: most re-export the
`/api` handler, same Clerk authz; `body/*`, `pro` and `billing/apple/*` are native-only
projections). One call stays web-internal: `/api/coach/chat`, which has no `/api/v1` twin yet.
Its tools no longer act without asking — calendar changes wait for the athlete's approval, on
the web and here — so moving it is a web task, not a design one.

**Writes.** A write never makes the athlete wait: the change shows on the tap and goes out behind.
Every write goes through `SharpitRetry`: a dropped connection, a timeout, a 429 or a 5xx is tried again
(four tries, 1 s, 2 s, 4 s apart); a refusal (4xx, a session gone) is not, since the same request gets
the same answer. Only a write that fails for good is said — inline where the screen has an error line,
otherwise in the app's toast through `SharpitWriteFailures`, which `RootView` watches, because a sheet
or a form may be closed by then. `AthleteProfileStore.save` applies the patch to the profile at once
(`V1AthleteProfile.applying`, merging `notificationPrefs` and `featurePrefs` as the server does),
queues the writes in order, and reads the profile back when one fails for good; `settle()` waits for
the queue. The morning check-in closes on the tap the same way. A creation that needs the server's id
(a goal, a coach constraint) and the consents (the gate reads them) still wait for the answer, retried.
Clients map a 5xx to `SharpitAPIError.server` so it can be told from a refusal. The journal says
what the server refused (400/422 carry its message, 429 is `rateLimited`) and sends its saves one
at a time (`JournalStore.saveChain`), so a save retried in the background never races the next.

`AthleteProfilePatch` carries only the fields the athlete changed — an absent key means
"leave it" and an explicit `null` means "clear it", a distinction a `Codable` struct of
optionals cannot express. The web's validator records why: a PATCH that materialised the
fields it had not been given once wiped an athlete's thresholds on a one-field save.

**Pro gating.** Pro gates what SHARPIT adds — analyses, computed metrics, pushes to the watch —
never the athlete's own data, with one exception the athlete chose (`docs/adr/0011`): the extra
widgets (Sommeil, Poids, Volume, Régularité, Prochain objectif) are Pro — `ProStore` writes the tier
into the snapshot, a locked widget draws `WidgetProLocked`. The plan's copy into the iPhone's
Calendar is free (`docs/adr/0016`, superseding 0011's calendar part): once Apple Calendar is linked,
`AppleCalendarSync` makes the chosen calendar equal to the next 21 days of the plan — on link and on
the reminders' beats (launch, foreground, `calendarRevision`), events keyed by
`sharpit://plan/session/<id>`, the « SharpIt » calendar removed on unlink. `SharpitProTeaser` stands where such a feature would sit below Pro
and opens `ProView`; the server decides, the app only reflects `pro_required`.

**Native never calls `/api/presentation/*`** — see SHARPIT ADR-040. The web presentation
layer is web-only; the app maps domain payloads itself.

**Persistence.** SwiftData, two models keyed by `trainingDayId`: `TodayDaySnapshot` holds the raw
encoded `V1TodayResponse`, `JournalDaySnapshot` holds a day's entry, preferences and derived
checklist. One repository each, and they are the only accessors, so both screens paint offline
before the network answers.

The cache is never the truth — the server is. A write goes to `/api`, the cache is written from
the server's echo and never merged with it. It stays on the iPhone (`cloudKitDatabase: .none`,
`docs/adr/0009`): every model holds health-derived data, which Apple forbids in iCloud. The
schema keeps the shape CloudKit once required (`docs/adr/0007`) — no `#Unique`, so each
repository resolves a day by fetching every row for it sorted by `fetchedAt` descending, keeping
the newest and deleting the rest; a default on every attribute and an optional payload.

**Local data belongs to an account.** Nothing cached on the iPhone is keyed by account, so
`LocalAccountData` records the Clerk user it was written for (`AuthGate` claims it on each
sign-in): another account wipes the SwiftData snapshots, the cached answers and the activity files
first, and deleting the account wipes them at once.

**Drawers close by a swipe.** A drawer with a drag indicator carries no « Fermer »: its « … » is
its only bar item (`PlannedSessionDrawer`, `BrickSessionDrawer`, `DoneBrickDrawer`). A form keeps
its Annuler, a task sheet its Fermer.

**Reading density.** `displayMode` (`essential` / `expert`) is read once into a
`DisplayModeStore` in the environment; a surface asks `\.isExpertReading` rather than the
profile (`docs/adr/0006`). It governs what is shown and how it is named, never what is
measured — session load appears in both readings, as « charge 78 » or « 78 TSS », mirroring
the web's `formatTrainingLoad`. In expert, Activité adds « Analyse technique » (the streams' `analysis`) and Plan adds « Forme » (`/api/v1/training-load`: CTL/ATL/TSB, weekly TSS); the picker page lists exactly that. It is a reading preference, not an access tier: `tier`
(FREE / PRO) gates features, the density gates nothing.

**Weather** comes from WeatherKit + Core Location (`LocationWeatherService`), never from
the API.

**Framework callbacks.** Callbacks handed to system frameworks (Speech, AVAudio, HealthKit…) are
built in nonisolated functions: main-actor closures trap when the framework calls them on its own
queue.

## Design system

`SHARPIT-APP/DesignSystem/` is the only place that defines tokens and shared components.

The source of truth is the web design system, not this repo:

- Law: `../SHARPIT-WEBAPP/design.md` and `../SHARPIT-WEBAPP/docs/design/DESIGN_LANGUAGE.md`
- Values: `../SHARPIT-WEBAPP/packages/app/src/lib/brand/brand-tokens.ts` and
  `../SHARPIT-WEBAPP/packages/ui/src/styles/globals.css` — colours **and geometry** (radii, paddings,
  sizes) reach `SharpitTokens` through `yarn tokens:ios`

The brand is **Ink & Lime** (SHARPIT-WEBAPP ADR-085, `docs/adr/0012`): a cool off-white canvas, white
cards (28 pt corner, soft wide shadow, no border), ink figures and icon tiles, lime as the only hue,
SF Pro with heavy tabular figures. The look is the seven reference cards in
`../SHARPIT-WEBAPP/docs/design/reference/ink-and-lime/`; the Debug gallery rebuilds them from the
components (`defaults write app.sharpit.ios SharpitDesignGallery -bool YES` in the simulator) — new
work should look like it. A sport is told by its glyph in the ink tile, never by a colour. Apple
chrome (tab bar, navigation, Liquid Glass) stays system; brand meaning lives in the content.

Liquid Glass is chrome only: the tab and navigation bars, toolbar controls — Plan's
`SharpitTodayButton` sits there, left of its title; the day screens put « Aujourd'hui » beside
the date instead (`SharpitTodayChip` in `DayDetailDatePicker`), since in the bar it merged into one
glass pill with each screen's own actions — and controls floating over scrolled content (the coach's composer, the
docked actions of the onboarding and the consent wall; `sharpitGlassControl`,
`sharpitGlassButton`). Content surfaces never take glass. The month view is `UICalendarView`
(`SharpitCalendarSheet`) so a day can carry a mark: filled for an activity or data, a ring for
a session ahead, muted for one missed or a day read empty.

Switches are lime on every page (`SharpitSwitchStyle`, set at the app's root): the app tint is
`primary`, near-white in dark mode, which left a white knob on a white track.

Elevation: surfaces have no hairline border; on light a card lifts with one soft, wide shadow
(`sharpitShadow(.panel)`), on dark by luminosity only. Inside a card, rows sit white in a grey
`SharpitInsetGroup`, separated by air. Every sheet uses `.sharpitSheet()` so none falls back to system black, and
no screen uses `Color(uiColor: .systemBackground)`.

Color and affordance (`docs/adr/0004`): figures and status words are ink; only caution and risk
keep a hue (`RecoveryReadout.tone`). The intensity ramp of `SessionFeedbackTone` (light grey → lime)
is for fills — a rating grid's ticks, a bar — never for type on a white card. Anything that opens something is a raised tile with a chevron and
`.buttonStyle(.sharpitPressable)`, and `CoachDiscussButton` is a tinted pill placed with
the title of what it discusses — never at the bottom of a screen. Session feeling is written in the web's words (`SessionFeeling.storedValue`).

Motion: `SharpitMotion.selection` for controls under the finger, `reveal` for content
arriving; `staggerDelay(index:)` is capped, so use it instead of hard-coded delays.
`.revealed(_:index:)` applies that reveal-and-stagger to a view arriving on screen.
`SharpitTickGauge` is animatable: a score changed inside an animation sweeps the ticks.

The brand mark is the app icon's (`SharpIt.icon`: six dots on a hexagon, `circle.hexagonpath.fill`
in `SharpitColor.brandMarkGradient`); `SharpitLaunchMark` shows it while a screen cannot be drawn
yet. The web's favicons and PWA icons carry the same mark. A cold launch shows one loading screen,
`SharpitLaunchSplash` (the mark breathing, a lime arc once the wait passes 0.45 s), held by
`LaunchCurtain` until the landing screen can be drawn whole — Résumé out of `.loading` (the cached
snapshot counts), or the sign-in, the wall, the wizard or another tab — for at least 0.6 s and at
most 3.5 s; it leaves growing as it fades, and Résumé's arrival waits for it so it plays on the
hand-over. Never shown again on a return from the background.

What makes a surface feel finished, applied everywhere new work lands:

- **One component per recurring shape.** Every card opens with `SharpitCardHeader` (icon tile,
  title, subtitle, accessory, chevron); figures use `SharpitHeroFigure` / `SharpitRowFigure`, pills
  `SharpitPill`, bars `SharpitProgressBar` / `SharpitGoalTrack`, rows `SharpitInsetGroup` /
  `SharpitInsetRow` with `SharpitNumberChip` / `SharpitCheckBox`, actions `SharpitPrimaryButton`
  (primary / accent / secondary); never a local copy that drifts a point. Symbols are stroked in content; filled only for a status mark (a check, a seal).
- **Anticipate.** A screen fetches what is stale before being asked (providers are pulled on launch
  and foreground, `ProviderSyncStore`) and says it quietly, never with a blocking state.
- **Announce news, not work.** After a sync, say what came in (« 3 aliments ajoutés »); say « à jour »
  only when the athlete asked.
- **Reward, don't nag.** A kept day earns its seal (`NutritionGoalSeal`), found by opening it. No
  streak counters.
- **No dead ends.** An empty day offers the next step (sync, another day, link a source); a
  failure names its cause and the fix (`SharpitErrorGuidance`: network, session, server).
- **Haptics: a notch under the finger, nothing else.** A ruler's units, days painted, a curve
  scrubbed — the finger dialling. Never a tap, a choice, a toggle, a send, a success or navigation:
  the screen already shows it, and felt everywhere it read as noise (the athlete's call,
  2026-10-05). `SharpitHaptics` has no other kind, on purpose.
- **Haptics through `SharpitHaptics` only** — Core Haptics. On the athlete's iPhone neither
  `UIFeedbackGenerator` nor SwiftUI's `sensoryFeedback` played anything in the app, while a Core
  Haptics transient did; never reach for either.
- **Animate meaning only.** Figures move between days and a seal arrives once; nothing animates on
  input or on every refresh, and `SharpitMotion` honours Reduce Motion.

Screen structure follows the web causal column: state → evidence → recommendation →
projection → limit → confidence.

No wash in content. Each tab leads with at most one ink card — Résumé's verdict, the weekly
review's hero, Santé's age — the rest are white cards.

Corners nest concentrically (HIG, iOS 26). A container declares its corner
(`sharpitContainerCorner`, done by every `sharpitSurface`); what sits inside fills with
`sharpitConcentricBackground(_:minimum:)` — chips, tiles, buttons, segments — never a fixed
`RoundedRectangle`, so a button docked at a sheet's foot follows the sheet's curve. The token radius
is the minimum; before iOS 26 it is the corner. Strokes keep a fixed shape (ConcentricRectangle is
not insettable).

Text sizes. `SharpitTypography` scales its fonts through `UIFontMetrics`, so `.dynamicTypeSize(...)`
caps do not reach them: a layout that cannot grow adapts instead. At the accessibility sizes
(`dynamicTypeSize.isAccessibilitySize`) side-by-side rows stack — `SharpitCardHeader` puts its
accessory on its own line and drops the tile, the strength rows, the morning proposal, the wellness
row and Régularité's foot go vertical — fixed text columns are `@ScaledMetric`, and
`SharpitRowFigure` and the dial centre shrink to fit. Formatters read NaN, ∞ or a value beyond `Int`
as « — » (`Int(exactly:)`), never trap. The Debug screen demo carries `stress`, `stress-sleep` and
`stress-strength` (six-figure volumes, two-line names, a 23 h 59 night) to check it on iPhone mini
with `xcrun simctl ui booted content_size accessibility-extra-extra-extra-large`.

No card in a card. Rows inside a card (`SharpitInsetGroup`, `.sharpitSurface(.row)`) read straight on
it, split by hairlines as Apple's grouped lists are — no grey group, no white box per row.

Notifications speak as a coach who knows the athlete: « tu », warm and plain (« Ta séance t'attend
à 18:00 », « Dommage pour hier », « On se retrouve demain pour ton vélo endurance »), one honest
remark at most, every figure true — never hype, emoji, praise for its own sake or guilt. The server
writes the pushes (`session-alerts.ts`, `athlete-notifications.ts`); the app its local reminders.

Forbidden, on both platforms: streak counters, radial gauges dominating a hero, sparkle /
chatbot chrome, colored glow shadows, invented metrics, motivational micro-copy.

## Related specs

`docs/superpowers/specs/` holds the design and parity specs. Read the most recent one on a
subject before changing that subject — earlier specs are superseded, not merged.

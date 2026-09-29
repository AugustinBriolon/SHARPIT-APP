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

WeatherKit, HealthKit, CloudKit and Push Notifications (`aps-environment`) are all entitled in
`SharpIt.entitlements` and all need a paid team. `Config/Info-Extra.plist` declares the
`remote-notification` background mode: CloudKit's sync pushes and the morning-verdict APNs
push both need it. Automatic signing stamps `aps-environment` as `production` on an archive, so
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
than reaching for Clerk themselves.

**Consent.** `AccountGate` sits between `AuthGate` and `RootView`. A new account meets the
consents inside the onboarding, as its step just before Sources; the legal wall
(`PrivacyConsentWallView`, the web's `/consent`) stands only in front of an athlete already
onboarded. CGU, Politique de confidentialité and the health consent are required together (the
server refuses one without the other), AI processing and the unofficial-providers notice are
optional; the wizard's « Tout accepter » ticks all five, since the first week needs AI. The wall's
reason and the version in force come from `/api/v1/privacy/consent` (`V1PrivacyConsents.wallReason`
mirrors `needsLegalConsentFromProfile`), so a new version of the documents brings the wall back
without an app release. The documents are the web's published `/terms` and `/privacy`, opened
in-app (`LegalDocumentSheet`) — never a bundled copy. Paramètres → Confidentialité & conditions
changes each consent; withdrawing health reports to the gate through the environment and the wall
stands again. It also deletes the account (`/api/v1/privacy/delete`: data, provider access and
the Clerk identity, then a local sign-out; the server e-mails a confirmation). A subscription that
still renews is named in the confirmation, with the App Store's subscription sheet one tap away:
deleting an account cannot cancel it; Compte ends with an immediate sign-out.

**Onboarding.** A new account answers the first-login wizard before it sees the tabs: Toi (first
name, sex, height, birth date) → Sports → Matériel → Ta semaine → Objectif → Blessures →
Confidentialité (only when owed) → Sources → Première semaine (`OnboardingStep`). The server
decides who owes it (`onboardingCompletedAt` present and `null` on `/api/v1/athlete-profile`); the
phone only remembers a "done" per Clerk user, so a finished athlete never waits on a profile read,
and a read that fails lets the athlete in without remembering anything. `AccountGateModel` owns the
`OnboardingStore`, so a session refresh that resolves the gate again never rebuilds the wizard, and
`OnboardingStepMemory` reopens the step reached after a quit. Each step is written as the athlete
leaves it: the first name on the Clerk user, the body, practiced sports, equipment,
`trainingAvailability`, a first goal through `/api/v1/goals` (its place picked from MapKit
suggestions, `OnboardingPlaceField`), the injuries as physical notes (`/api/v1/physical-notes`, which
the coach reads as sensitive zones) and the consents. Injuries are health data: while the consents
are owed they wait on the phone and are written with the privacy step, before the week is planned.
A tap carries the step it was made on, so one delivered again after the page moved is dropped
instead of skipping a step. Once the consents allow AI, the store asks `/api/v1/coach/plan` for the
next seven days — towards the goal just created — while the athlete links their sources; « Ajouter
à mon plan » sends the week back whole to `/api/v1/coach/plan/insert`, which stores it through the
web generator's own mapping (the coach's strength and endurance prescriptions included) or refuses
it before writing anything; Plan's generator uses the same route. Then `/api/v1/onboarding/complete`
finishes the wizard. Without AI consent the step says so and finishes without a week. Sources links
Garmin in-app through `GarminConnect` (SHARPIT ADR-047), switches Apple Health on — a switch per
Clerk account (`AppleHealthSource.bind(userId:)`), so a new account on the same iPhone starts off
— and links MyFitnessPal (`MyFitnessPalConnectSheet`). Debug builds open the wizard on in-memory
services with the `-SharpitOnboardingDemo` launch argument (`OnboardingDemoHost`).

The page is one page: the header's tick dial (`SharpitTickGauge`, animatable, so it sweeps from step
to step) and the step's title stay put, and only the content under them slides in from the side the
athlete is heading. The dial's thumb shows from the first step, at its start, with the position
(« 1 / 9 ») inside the arc. A choice is seen by its fill and felt by a light haptic — no symbol
animates (a wiggle on every tile read as unfinished); triathlon is the app's own symbol
(`triathlon.circles` in the asset catalog), SF Symbols drawing none. Toi uses the design system's
inputs: `SharpitFormField` (the label above a soft well, a ring while focused — no card),
`SharpitSegmentedChoice` for the sex, `SharpitRulerPicker` for the height (a tape measure settling
on each centimetre, firmer on the tens — `SharpitHaptics`, Core Haptics, prepared as the finger
lands — nil until moved) and `SharpitDateField` (the age beside it, the wheel in a
short sheet: opened in place it grew the page into a scroll).

**Shell.** `RootView` is a five-tab `TabView` (Résumé / Plan / Coach / Activité / Santé).
Paramètres is not a tab: it is a sheet (`SettingsView`) opened through `ShellRouter.openSettings()`
from the avatar (`AccountAvatarButton`, the Clerk photo or the initials) in Résumé's header, or a
`/settings` link. Résumé's date is its large title, folding into the centre of the bar on scroll as Santé's does;
the mode, Journal and weather are the fold's first row of glass chips (`sharpitGlassChip`) and
scroll away with it. Goals open from Plan's « … »
menu, the coach's memory (context, trips) from Coach's toolbar.

**Plan generation and weekly review.** « Remplir ma semaine » is generated on the server in the
background (`/api/v1/coach/plan/jobs`, `PlanJobServing`): the app starts the job, follows its
drafts while in front, and picks it back up on its return (`PlanGenerationStore.resume`); the
server pushes « Ta semaine est prête » (`/plan/generator`, which opens Plan's generator through
`ShellRouter.isShowingPlanGenerator`), app open or not. The store is owned by `PlanView`. The
sessions appear one by one (`GeneratedWeekView`, shared with the onboarding's first week, which
still streams `/api/v1/coach/plan`). The server's Gate takes out what it rejects before the week
is shown, so « Ajouter » (`/api/v1/coach/plan/insert`) is never refused for safety.
While the coach writes, `GeneratingWeekView` names what it reads, one line after another
(`readingSteps`), then the sessions so far, with redacted rows still to come. A proposed session
opens on `ProposedSessionPage`, pushed inside the generator's sheet (HIG: one sheet at a time) and
a sheet only in the onboarding — the system's own transitions: a zoom from the row, tried, read as
the sheet vanishing. It shares `PlannedSessionSummary` with `PlannedSessionDrawer`, fed by
`PlannedSessionPreview(generated:)`: the steps (`breakdown`, resolved server-side like a planned
session's) and the coach's one-line rationale — no prose instruction, the coach writes none.
The row opens the session; its check is a button of its own.
A brick (legs sharing `brickGroupId`) is one entry in Plan (`PlanEntry.brick`, `PlanBrickCard`) and one
line in Résumé (`brickLegs`), and opens `BrickSessionDrawer`: the chain, the legs with their steps and the
transition between them; a leg pushes the single session's drawer (`isEmbedded`) for the watch and linking.
One leg left is a plain session, as the web demotes it. A breakdown's repeated steps are gathered by their
server `group` (`PlannedStepSet`) under one « N fois » well — the block and its recovery, N times.
« Ajuster le planning » (`PlanAdapterSheet`, its `PlanAdjustmentStore` owned by `PlanView`) is laid
out as the generator — `CoachWorkingHeader`, `SharpitActionDock`, `SharpitPrimaryButton`, rows with
`SharpitSportBadge` and `SharpitKeepToggle` — and never shows the model's reasoning. The server
takes out the changes its Gate rejects; the ones kept go back whole (`V1AdaptChange.applyBody`) to
`/api/v1/coach/adapt/apply`, which stores them through the web adapter's own mapping, the coach's
steps included.
« Bilan de la semaine » (Plan's « … ») is SharpIt Pro: `WeeklyReviewView` reads the latest review
from `/api/v1/coach/weekly-review`, writes the current week's on demand, and shows a
`SharpitProTeaser` on the server's 403. It is laid out like Health's summary: « Faits marquants »
(what went well, what to watch — split from the markdown's fixed headings by
`WeeklyReviewSections`), the week's figures as metric cards with quiet day bars and the average
dashed, next week, and the full text on its own page. `-SharpitWeeklyReviewDemo` shows it on a
fixed week in Debug builds.

**Widgets.** `SharpItWidgets` is a WidgetKit extension (« Séance du jour », « Verdict du jour »,
« Nutrition », « Sommeil », « Poids », « Volume de la semaine », « Régularité », « Prochain objectif »,
« Demander au coach » and its Control Center button; home screen and lock screen). The snapshot is in
sections — `day` (verdict, sessions, last night's sleep) and `regularity` from Résumé's fold,
`nutrition` from the food log card (`NutritionTodayStore`), `weight` from Santé's body overview (`CorpsStore`) and the
profile's target, `training` (the last two weeks recorded) from Activité's list, `goal` (Objectifs'
next race, `GoalOrdering.nextRace`) from `GoalStore` — each written by the screen that reads it and
merged (`WidgetSnapshotStore.update`); the silent push reads them all. The volume widget is an
`AppIntentConfiguration` (`VolumeSport`): kilometres for one sport, time for strength or all sports,
Monday first, with last week at the same point as a fact, never a verdict. No streaks. `/goals`
opens Plan's Objectifs (`ShellRouter.isShowingGoals`). How a section reads (the dial's figure, the target line) is in `WidgetSnapshotReadout`, shared
and tested; the energy and sleep dials are the app's `SharpitTickGauge` (`DialReadout`). A widget never calls the API — no Clerk session, a small reload
budget: the app writes a `WidgetSnapshot` into the App Group `group.app.sharpit.ios`
(`WidgetSnapshotStore`) from Résumé's fold each time it reads today, and on a silent push the
server sends after each scheduled sync (`refresh: today`), then reloads the timelines. A snapshot
of another day shows as stale, never as today; signing out or a new account erases it.
Every home-screen widget is built on `WidgetFrame` (`WidgetStyle.swift`): one header — its name
and one glyph, same height and gap on every widget — then the body anchored to the bottom, with one
type scale (`WidgetHero` for the main number, `WidgetTitle`, `WidgetCaption`) and `WidgetMetrics`;
a widget never lays out its own header. A widget draws the app's canvas (`SharpitCanvasTexture`: dot grid, brand halos; the verdict adds a
halo in its posture's tone) and speaks its type — the brand faces are registered in the extension
too. A session opens itself: `https://sharpit.app/activity/<id>` once done (Activité pushes its
detail), `/plan/session/<id>` before (Plan opens today's week and the session's drawer).
`SharpItShared/` is compiled into both targets: the generated tokens (`yarn tokens:ios` writes
there), the typography and its fonts (`scripts/fetch-brand-fonts.sh` writes there), the canvas
texture, `V1ActivityType` with its identity color, `V1TodayPosture` with its tone, and the snapshot.
The target was added by hand to `project.pbxproj` (IDs `…05…`); its Info.plist and entitlements are
in `Config/`.

**Objectifs.** `GoalsView` is one list, no tabs: the next race on the ink plate
(`GoalOrdering.nextRace`: the nearest A race ahead, else the nearest race), the goals in progress,
then — further down, only when there are any — the goals reached. Its `GoalStore` is owned by
`PlanView`, so reopening Objectifs shows the goals at once and refreshes them quietly. A goal
(`GoalDetailView`) and a new goal (`GoalCreateView`) are pages pushed in the Objectifs stack, never a
sheet over the Objectifs sheet.

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
Clients map a 5xx to `SharpitAPIError.server` so it can be told from a refusal.

**Coach turns and proposals.** A coach turn is kept as the AI SDK's UI-message parts
(`CoachMessage.parts`), rebuilt from the route's stream by `CoachUIMessageAssembler` — a port of
the SDK's `processUIMessageStream` — and sent back whole: on the next question, on an approval,
and in the saved thread. Nothing in them is trimmed, because the server replays them: provider
metadata carries the model's thought signatures, and an approval carries the server's
`signature`. A calendar tool (`CoachUIParts.calendarToolTypes`) that stops at
`approval-requested` is a `CoachProposalCard` (Valider / Refuser, a second « Confirmer » for a
deletion); once every proposal of the step has an answer, `CoachStore.respond` sends the turn
back and the server carries out the approved ones and goes on writing in the same message, as
`useChat`'s `sendAutomaticallyWhen` does. A new question refuses the proposals left open
(`dismissingUnresolved`), and an applied change bumps `ShellRouter.calendarRevision` so Plan and
Résumé reload. The wording follows the web's `coach-tool-approval-helpers.tsx`.

**Coach history.** The server keeps the conversations and the client saves the whole thread
after each answer, as the web does. A turn opened from history keeps its stored JSON
(`CoachMessage.stored`) and goes back as it came, its parts brought up to date. The chat route
reports model and gateway failures *inside* a 200 stream (an `error` event); `CoachChatClient`
turns it into `CoachChatError` and logs the chunk kinds of every answer under the `coach`
category, so a silent answer names its cause.

**Journal.** `JournalView` asks for the day signals the athlete turned on, and
`JournalPrefsDrawer` chooses them. Preferences are kept as the raw JSON the server sent
(`JournalPrefs.raw`): the web stores keys the app does not model — diet flags, nutrition
panel, thresholds — and the server rebuilds its enable map from defaults for every key a
payload omits, so sending back only what the app renders would silently reset the rest. The
catalogue in `JournalTrackables.swift` therefore covers the signals the app can render, never
all of the web's.

Humeur reads the morning check-in (`/api/v1/wellness-checkin`) when the journal row carries no mood — the mood lives there, the row only echoes it when answered from the journal; a day with only a check-in counts as noted, here and in the server's journal data days. The day picker marks the journal as the day screens mark their data (`SharpitDataDayMark`): a dot where something was noted, a ring where the day was read and holds nothing, nothing while unknown — from `/api/v1/data-days?domain=journal`. The journal and the day screens read their marks through one `DataDaysMarker`: the 91-day window holding the week in view first (the strip scrolled back, a month opened), then the rest of the history in a task of its own that a screen left mid-way does not cancel; a window that failed is read again when next needed. The journal's skeleton is its own rows redacted, under a date picker that stays put.

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

**Day drill-downs.** Sleep and Recovery open from the Today gauges, Nutrition from Résumé's
nutrition card (`NutritionTodayCard`, below Régularité). All three are a
`DayResourceStore` inside `DayDetailScaffold`, which pins the day picker
(`DayDetailDatePicker`, built on the Plan's `SharpitWeekStrip`) above the content; a new
day's drill-down is a v1 resource plus a sections view, not a new store. The store keeps every day it
read for the life of the screen (a day seen again appears at once and refreshes behind), marks the
picker's history (`SharpitWeeks.history`, three years — Plan, Journal and the day screens share it) from `/api/v1/data-days` through `DataDaysMarker` (so a logged day is marked before it is
opened), and reads the six most recent days with data ahead of the athlete.

**Nutrition.** The food log is the athlete's own data and open to everyone; only the coach's
reading is SharpIt Pro (the server sends `{ state: 'pro_required' }` below it and never generates
it), and `NutritionView` shows a `SharpitProTeaser` in its place. `NutritionTodayStore` maps the
answer to the card's states (disconnected, empty, loaded, failed — a failed read says so and opens
the day, which can retry). `NutritionView` is native, not the web's page: the energy on the app's
tick dial (`SharpitTickGauge`) with goal, exercise and remaining under it, the coach's reading on
the ink plate, the three macros as tiles and the energy split by macro, the meals as a list whose
rows push `NutritionMealView` (entries heaviest first, with the coach's flags), and 14 days of regularity against the calorie goal
(each day's adherence is the server's; the strip reads, it does not navigate). A header carries the
diet in force (from the journal) and the coach pill; the « … » menu syncs MFP, opens the weight
target (`WeightTargetSheet`) or creates one, and opens the coach. The Résumé card follows the gauge cells: tinted badge, energy against
the goal, the macros as columns, a context capsule. Goals, percentages and the reading are the
web's; `NutritionReadout` formats them and derives only the energy split (Atwater). The food log is
MyFitnessPal. It links in the app (`MyFitnessPalConnectSheet`): the athlete signs in on MFP's own
site in a private web view, the app reads the session cookie next-auth sets (whole or chunked) and
posts it to `/api/v1/myfitnesspal/connect` — the web asks for the same cookie copied by hand.
Nutrition syncs MFP alone (`/api/v1/myfitnesspal/sync`, toolbar or pull) and forgets every day read;
Sources de données links, syncs and unlinks it too. A day without a log draws its own empty plate
(never the scaffold's generic empty screen), and a missing log shows the link plate.

**Pro gating.** Pro gates what SHARPIT adds — analyses, computed metrics, pushes to the watch —
never the athlete's own data. `SharpitProTeaser` stands where such a feature would sit below Pro
and opens `ProView`; the server decides, the app only reflects `pro_required`.

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

**Local data belongs to an account.** Nothing cached on the iPhone is keyed by account, so
`LocalAccountData` records the Clerk user it was written for (`AuthGate` claims it on each
sign-in): another account wipes the SwiftData snapshots, the cached answers and the activity files
first, and deleting the account wipes them at once.

**Freshness.** The app starts provider pulls itself (`ProviderSyncStore`, `/api/v1/sync`)
on launch, foreground and pull-to-refresh, and can send Apple Health day summaries
(`AppleHealthSource`, `/api/v1/health-samples`) when the athlete switches it on in Paramètres → Sources de données.
The regular pull only reaches back to the last one, so `GarminHistoryImport` runs the web's
full-history Garmin import once per Clerk user, the first time Garmin is seen connected
(launch, foreground, or the Garmin handoff). It is remembered only once it finished; a run cut
off by the server's five-minute limit is picked up on the next foreground, and the server skips
what it already holds. Streams are not in that pass: `/api/v1/sync` backfills them a batch at a
time. Apple Health only fills gaps; Garmin stays the reference (`docs/adr/0005`, SHARPIT
ADR-043) — yet it is enough on its own: an Apple Watch without Garmin gets the whole app.
Switching it on sends the last year, then each sync sends what came in since, a marker per kind
and per account moving forward batch by batch (so a send cut short picks up where it stopped):
the days (`/api/v1/health-samples`, 31 per call, the last week always re-sent; the server turns
them into the Core's sleep, HRV and resting-HR observations) and the workouts
(`/api/v1/health-workouts`, five per call, a month read at a time — `HealthWorkout`, its heart
rate and route laid on one 5-second axis by `HealthWorkoutStreamBuilder`). The server stores a
workout as an activity only while no Garmin or Strava account is connected; it answers
`acceptsWorkouts: false` otherwise and the app stops sending them. HealthKit is read-only and entitled in `SharpIt.entitlements`. Paramètres → Sources de données also offers the import on demand
(`GarminHistoryImport.importAll`), whether or not a run already finished.

**Activity cache.** The list (`ActivityView`) is one scroll view for every phase, holding the
refresh control: swapping the scroll view with the phase left the control stuck pulled down. An activity's detail and streams are kept on disk as the raw JSON the server
answered (`ActivityDiskCache`, Application Support), because the in-memory cache died with each
screen's client and the heaviest read in the app reloaded on every open. `ActivityClient` reads
memory, then disk, then the network: a stream is kept for good once the server said it was
available (a recorded session's samples do not change), a detail for 12 h
(`ActivityCachePolicy`) and any age when the network fails. The app's own edits keep it true — a
generated narrative rewrites the detail, a subjective rating drops it. A planned session's breakdown, which Today's
payload does not carry, is kept there too: the drawer opens on the last one read and asks the
plan again behind it, since a plan is edited where a recorded session is not.

**Santé.** The athlete's health as a check-up (`SanteView`, SHARPIT ADR-053), ranked by what
matters most: « Bilan du mois » (the biological age, how many markers sit in their norm, up to three
that moved), « À surveiller » (only when something deserves attention — resting HR up for days, HRV
under the athlete's range, short nights, a fast weight change, an active sensitive zone), then
« Signes vitaux » (resting HR, HRV, sleep, VO₂max), « Corps » (weight with its target, body fat,
visceral fat, muscle) and « Au quotidien » (steps, breathing during sleep). Everything comes from
`/api/v1/health/overview` (`SanteStore`, kept whole in the response cache so the page paints
offline): each marker read against a published norm, its source named, and against the athlete's
own month — the app computes none of it; `SanteReadout` only words it. A marker opens
`CorpsMetricDrawer` with its reading (`SanteReadingBlock`) when the web keeps its longer history
(`/api/v1/body/series`, through `CorpsStore`, which also still feeds the Poids widget), else its month
(`SanteMarkerSheet`). Free except the biological age, which is Pro (`SharpitProTeaser`); Pro without
the data it needs pushes `AccountView`. The weight target is set from the toolbar
(`WeightTargetSheet`), the sleep targets from Sommeil's (`SleepTargetsSheet`). Training thresholds are
not health: Paramètres › Entraînement › Seuils d'entraînement (`ThresholdsView`).

**Pages et widgets.** Paramètres › Pages et widgets (`FeaturesView`) turns a part of SharpIt off —
Journal, Nutrition, Santé, Régularité (`SharpitFeature`). Each row says « Affiché » or « Masqué » and opens
its own page (`FeatureDetailView`): what it looks like (`FeatureShowcase`, the app's own components on example
figures, so the picture never drifts from the screen), the switch, why follow it and where it shows. Off, it disappears everywhere it shows: the
Résumé chip or card, the page, the Santé tab, the home-screen widget (a placed widget says it is
hidden, `WidgetFeatureOff`); its data is kept. `FeatureStore` in the environment (`\.features`)
holds the choice, saved to the account (`featurePrefs` on the profile, merged server-side like
`notificationPrefs`), applied at once and put back if the save fails; the last choice is kept in the
widget snapshot so the app opens with the right tabs.

**Paramètres.** A page of cards: the account and tier, the SharpIt Pro plate, then the one setting
answered in place — Apparence (`AppearancePreference`, per iPhone, applied to every window's
`overrideUserInterfaceStyle` so open sheets switch at once) — then Notifications, a page
(`NotificationPrefsView`: the switch, `PushNotificationManager.setEnabled`, where off unregisters
the device server-side since iOS owns the permission, then each kind in `notificationPrefs`; session reminders are local — `SessionReminderScheduler`
reschedules them from the plan on launch, on each return, on `calendarRevision` and on the switch,
an hour before a session's `startTime` or at 7:30 that day, by `SessionReminderPlanner`'s rules; every
tapped notification goes through `PushNotificationManager.destination(for:)` to
`ShellRouter.open(_:)` — `/plan/generator`, `/plan/review`, `/settings/sources`, a tab), Sources de
données, Synchronisation iCloud (`CloudSyncMonitor`, which records `NSPersistentCloudKitContainer`
events from launch), Sports & équipement (the onboarding's own `SportChoiceGroups` and `EquipmentBySport`, saved as they change; the sports wait while no endurance sport is picked), Densité de lecture (its own page: the choice needs its
explanation) and Confidentialité, each row saying its state before it is opened. A page's explanation is the footer of its
list (`SharpitListFooter`), never a paragraph above it. Compte edits in
place: first and last name through Clerk's `user.update`, sex, height and birth date through
`AthleteProfilePatch`; e-mail, password and photo stay in Clerk's own sheet.
`AthleteProfilePatch` carries only the fields the athlete changed — an absent key means
"leave it" and an explicit `null` means "clear it", a distinction a `Codable` struct of
optionals cannot express. The web's validator records why: a PATCH that materialised the
fields it had not been given once wiped an athlete's thresholds on a one-field save.

**SharpIt Pro.** StoreKit 2, verified by the web (SHARPIT ADR-044). `ProStore` reads
`/api/v1/pro` (tier, the web's perks, the subscription), carries the web's `appAccountToken` on
every purchase, and hands every transaction — a purchase in `ProView`'s `SubscriptionStoreView`,
`Transaction.unfinished` and `Transaction.updates` from launch, a restore — to
`/api/v1/billing/apple/verify`, finishing it only once the web has it. The app never decides the
tier. Products: `app.sharpit.ios.pro.monthly` and `.yearly` (`SharpitProProduct`), mirrored in
`Config/SharpitPro.storekit` for the simulator (select it in the scheme's Run → Options →
StoreKit Configuration).

**Reading density.** `displayMode` (`essential` / `expert`) is read once into a
`DisplayModeStore` in the environment; a surface asks `\.isExpertReading` rather than the
profile (`docs/adr/0006`). It governs what is shown and how it is named, never what is
measured — session load appears in both readings, as « charge 78 » or « 78 TSS », mirroring
the web's `formatTrainingLoad`. In expert, Activité adds « Analyse technique » (the streams' `analysis`) and Plan adds « Forme » (`/api/v1/training-load`: CTL/ATL/TSB, weekly TSS); the picker page lists exactly that. It is a reading preference, not an access tier: `tier`
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

Liquid Glass is chrome only: the tab and navigation bars, toolbar controls — the day
screens' `SharpitTodayButton` sits there, left of Plan's title and right of Sommeil's and
Récupération's — and controls floating over scrolled content (the coach's composer, the
docked actions of the onboarding and the consent wall; `sharpitGlassControl`,
`sharpitGlassButton`). Content surfaces never take glass. The month view is `UICalendarView`
(`SharpitCalendarSheet`) so a day can carry a mark: filled for an activity or data, a ring for
a session ahead, muted for one missed or a day read empty.

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
`.revealed(_:index:)` applies that reveal-and-stagger to a view arriving on screen.
`SharpitTickGauge` is animatable: a score changed inside an animation sweeps the ticks.

The brand mark is the app icon's (`SharpIt.icon`: six dots on a hexagon, `circle.hexagonpath.fill`
in `SharpitColor.brandMarkGradient`); `SharpitLaunchMark` shows it while a screen cannot be drawn
yet. The web's favicons and PWA icons carry the same mark.

What makes a surface feel finished, applied everywhere new work lands:

- **One component per recurring shape.** Every readout card uses `SharpitCardHeader` (badge,
  label, chevron) and `SharpitTelemetryCapsule` (the foot line); never a local copy that drifts a
  point. Symbols are stroked in content; filled only for a status mark (a check, a seal).
- **Anticipate.** A screen fetches what is stale before being asked (Nutrition pulls MFP on opening
  past 15 minutes) and says it quietly (a spinner beside the header), never with a blocking state.
- **Announce news, not work.** After a sync, say what came in (« 3 aliments ajoutés »); say « à jour »
  only when the athlete asked.
- **Reward, don't nag.** A kept day earns its seal (`NutritionGoalSeal`), found by opening it, with
  one haptic the first time. No streak counters.
- **No dead ends.** An empty day offers the next step (sync, another day, link a source); a
  failure names its cause and the fix (`SharpitErrorGuidance`: network, session, server) — an
  expired MFP session asks to reconnect.
- **Haptics confirm what the finger does, nothing else.** A notch dialled (a ruler, painted days),
  a choice picked (one `.soft`), a real success once (a source linked, the wizard's week set).
  Never navigation: continuing, a step changing, a field or a sheet opening. Everywhere at once
  read as noise.
- **Haptics through `SharpitHaptics` only** — Core Haptics. On the athlete's iPhone neither
  `UIFeedbackGenerator` nor SwiftUI's `sensoryFeedback` played anything in the app, while a Core
  Haptics transient did; never reach for either.
- **Animate meaning only.** Figures move between days and a seal arrives once; nothing animates on
  input or on every refresh, and `SharpitMotion` honours Reduce Motion.

Screen structure follows the web causal column: state → evidence → recommendation →
projection → limit → confidence.

Forbidden, on both platforms: streak counters, radial gauges dominating a hero, sparkle /
chatbot chrome, colored glow shadows, invented metrics, motivational micro-copy.

## Related specs

`docs/superpowers/specs/` holds the design and parity specs. Read the most recent one on a
subject before changing that subject — earlier specs are superseded, not merged.

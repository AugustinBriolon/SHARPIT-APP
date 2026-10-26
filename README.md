# SHARPIT-APP

Native iPhone client for [SHARPIT](https://github.com/AugustinBriolon/SHARPIT) — Athlete Operating System.

## Requirements

- Xcode 27 / Swift 6 language mode
- iPhone simulator (prefer iOS 27 for Liquid Glass)
- Clerk Native API enabled; same publishable key as the web app
- An API origin: Debug builds use the sibling repo SHARPIT running locally
  (`docker compose up -d` then `yarn dev`, serving `http://127.0.0.1:3000`), Release builds
  use `https://sharpit.app` — see [Pointing at a server](#pointing-at-a-server)

## Signing

**Simulator.** Clerk requires Keychain, so simulator builds use **Sign to Run Locally**
(`CODE_SIGN_IDENTITY=-`). Fully unsigned apps crash at launch with OSStatus `-34018`.

**iPhone.** The app target supports `iphoneos`, and device builds sign with the Apple
Development identity of your team. The team is per machine, so it lives in the gitignored
`Config/Local.xcconfig`, next to the API origin:

```
SHARPIT_API_ORIGIN = https:/$()/sharpit.app
DEVELOPMENT_TEAM = <your team id>
```

Find the team id in Xcode → Settings → Accounts, or with
`defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier`. Then pick the phone as the
run destination and press Run. On the phone, enable Developer Mode (Settings → Privacy &
Security), and trust the developer under Settings → General → VPN & Device Management the
first time. A free Personal Team signs for 7 days.

WeatherKit and HealthKit are entitled and need a paid team; on a free Personal Team the app
still builds and runs, but the weather chip reads "Météo indisponible" and Apple Health cannot
be enabled. Associated Domains is not entitled yet.

## Brand and type

The app speaks Ink & Lime (`docs/adr/0012`) in SF Pro, the system face — no fonts to fetch or
bundle. Colours and geometry come from the web repository through `yarn tokens:ios`. To see the
reference cards rebuilt from the components without an account, run a Debug build with:

```bash
xcrun simctl spawn booted defaults write app.sharpit.ios SharpitDesignGallery -bool YES
```

To check the screens against extreme values (six-figure volumes, very long names, a 23 h 59
night), open a stress screen and set the largest text size:

```bash
xcrun simctl spawn booted defaults write app.sharpit.ios SharpitScreenDemo stress
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large
```

`stress-sleep` and `stress-strength` cover the sleep page and the guided workout.

## Pointing at a server

The app speaks to the web app over `/api`, never to the database — the domain logic, the
Clerk session and athlete scoping are all server-side.

Each build carries its own origin, set in `Config/*.xcconfig` and copied into the
Info.plist as `SharpitAPIOrigin`, so a build opened from the home screen or TestFlight
knows where to go. `APIConfiguration.baseURL` lets a `SHARPIT_API_ORIGIN` environment
variable override it, which only exists when Xcode launches the app.

| Goal | Setting |
| --- | --- |
| Local full stack | Debug default, `http://127.0.0.1:3000` |
| Production on a phone or TestFlight | Release default, `https://sharpit.app` |
| Debug build against a deployed instance | `SHARPIT_API_ORIGIN = https:/$()/…` in `Config/Local.xcconfig` (gitignored) |
| Simulator against a preview, no rebuild | `SHARPIT_API_ORIGIN` in the scheme: Run → Arguments → Environment Variables |
| UI work, no server | use `FixtureTodayClient` |

`//` starts a comment in an xcconfig, so write the scheme's slashes as `https:/$()/host`.

## Build & test

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

TestFlight: archive the Release scheme, then upload with
`xcodebuild -exportArchive -archivePath <archive> -exportOptionsPlist Config/ExportOptions.plist -exportPath /tmp/SharpIt-export -allowProvisioningUpdates`,
or from Xcode → Organizer.

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs the same tests on every push to
`main` and every pull request: newest Xcode on a macOS runner, any iPhone simulator, no signing
(`CODE_SIGNING_ALLOWED=NO`) and no `Config/Local.xcconfig`.

## Architecture

- Auth: ClerkKit + ClerkKitUI (`AuthGate` → `AuthView` sheet)
- Crash reports: Sentry (EU), started first in `SharpitApp.init` and never in tests.
  `CrashReporting` sends no PII, no tracing, no screenshots, strips request bodies and URL
  queries, and tags a report with the Clerk user id only
- Shell: five tabs (Résumé / Plan / Coach / Activité / Moi)
- Résumé: `GET /api/v1/today` via `SharpitClient` + Bearer token from `clerk.auth.getToken()`.
  The server links the day's finished activities to their planned sessions on that read
  ([ADR-042](../SHARPIT/docs/adr/ADR-042-today-links-activities-on-read.md)), for today and
  yesterday only: an older day is read as it was (web ADR-101); a session it
  missed can be linked by hand from the planned session's drawer. A done brick is one entry in
  Plan and opens as one chain; once every leg is done, its evaluation (overall RPE, transitions, feeling, notes) is
  read and saved on tap through `/api/v1/planned-sessions/brick/evaluation` (web ADR-059).
- Coach: `/api/coach/chat` streams the answer; the conversation is kept server-side through
  `/api/coach/conversations`, and the history sheet lists, reopens and deletes them; a proposed
  session reads as a native workout card and the answer ends with tappable follow-up questions
  (web ADR-111)
- Sommeil / Récupération: drill-downs opened from the Today gauges, read from
  `/api/v1/sleep` and `/api/v1/recovery` (projections of the web's view models), with a day
  picker shared with Plan
- Freshness: Today starts a provider pull on launch, foreground and pull-to-refresh
  (`/api/v1/sync`), and Moi can switch on Apple Health as a gap-filling source, with a
  diagnostic of what Apple Health holds ([ADR 0005](docs/adr/0005-app-started-sync-and-apple-health.md))
- Garmin through the Connect Developer Program: connected with the in-app OAuth handoff
  ([ADR 0024](docs/adr/0024-garmin-connects-through-the-in-app-oauth-handoff.md)), and a Pro athlete
  sends a planned run, ride or pool session to the watch with the button docked under its drawer
  ([ADR 0025](docs/adr/0025-a-planned-session-is-sent-to-the-watch-from-its-drawer.md)). The drawer
  leads with the steps: figures and the coach's reason first, the total time, then mobility and
  stretches folded around the steps ([ADR 0027](docs/adr/0027-the-planned-session-drawer-leads-with-its-steps.md))
- Journal: the day's signals via `/api/day-journal`, and what it asks for via
  `/api/journal-prefs`. Preferences round-trip as raw JSON so the keys the app does not
  render — the nutrition panel, thresholds — survive a save from the phone.
  The drawer's Nutrition section also sets the diet followed (the web's `diet_*` keys), which
  Nutrition names and the coach reads the day against.
  Sections follow when a signal happened (Journée, Checklist auto, Nuit dernière, Signaux du
  jour), and the automatic checklist is read from `/api/journal/day-signals` rather than
  recomputed — the thresholds and sport rules live on the web
- Activity status: the training mode (actif / en pause / blessé / malade) via
  `/api/activity-status`, written on every pick from Today's toolbar
- Moi: a grouped hub mirroring the web's Réglages — Modèle (Corps, Seuils & repères),
  Compte (Profil), Préférences (densité de lecture), Données (Apple Santé,
  diagnostic), À propos. Profil and Seuils edit `/api/athlete-profile` through a partial
  PATCH that names only the fields the athlete changed; Corps reads `/api/body-composition`
  and is read-only, since a weigh-in is written by a scale
- Reading density: `displayMode` (essentiel / expert) read once into a `DisplayModeStore` in
  the environment. It chooses what is shown and how it is named, never what is measured;
  session load is visible in both readings, as « charge 78 » or « 78 TSS »
  ([ADR 0006](docs/adr/0006-reading-density-governs-the-technical-layer.md))
- Local cache: SwiftData snapshots of a day's Today and journal, so both screens paint before
  the network answers and offline. The server stays the source of truth — a write always goes
  to `/api` and the cache is written from its echo — and the cache never leaves the iPhone:
  it holds health-derived data, which Apple forbids in iCloud
  ([ADR 0009](docs/adr/0009-the-read-cache-stays-on-the-device.md)). Past days' reads (Résumé,
  Sommeil, Récupération, …) are also kept on disk as the server sent them, so they open without
  the network after a relaunch until the app writes something new, and the day screens read
  ahead three days at a time ([ADR 0021](docs/adr/0021-past-days-are-kept-on-disk-and-read-ahead-three-at-a-time.md))
- Weather chip: WeatherKit + Core Location (not API weather)
- Design system: `SHARPIT-APP/DesignSystem/`. Colour and radius are **generated** from the
  web design system — edit `../SHARPIT/src/lib/brand/brand-tokens.ts` or
  `../SHARPIT/src/app/globals.css`, run `yarn tokens:ios` there, and commit the regenerated
  `SharpitTokens.generated.swift` ([ADR-041](../SHARPIT/docs/adr/ADR-041-ios-design-tokens-generated-from-web.md)).
  Spec: `docs/superpowers/specs/2026-09-16-ios-design-system-design.md` (tokens, typography
  and spacing sections superseded by ADR-041)
- Elevation diverges from the web: no hairline borders, soft shadows on light, luminosity on
  dark, and every sheet raised off black through `.sharpitSheet()`
  ([ADR 0002](docs/adr/0002-soft-shadow-elevation-instead-of-hairline-borders.md))
- Hubs and forms: `SharpitHubGroup` draws a titled plate of destinations and owns the
  separators between them; `SharpitFieldGroup` / `SharpitField` are its form counterpart
- Semantic color, pressable tiles and the coach pill under each title
  ([ADR 0004](docs/adr/0004-semantic-color-and-a-tinted-coach-pill.md))
- Nutrition: the food log lives in SHARPIT (web ADR-061). Each meal has its « + »: search
  (`/api/v1/food-log/foods`: the athlete's own foods, « Aliments de base » from the ANSES Ciqual
  table (web ADR-065), then Open Food Facts), a VisionKit barcode
  scanner, a quick add or a custom food per 100 g; entries are edited or swiped away on the meal's
  page and the athlete's targets set from the « … » menu. Open Food Facts is only ever asked by the
  server, so the iPhone sends it nothing; « Données Open Food Facts (ODbL) » is shown where its
  products are listed. Each write goes out behind the tap (`FoodLogStore`), then
  `/api/v1/nutrition` is read again for the totals. Macro targets are set in grams or as % of the
  energy; « Mes aliments » lists, edits and deletes the athlete's own foods, from the add-food sheet
  or from Paramètres › Nutrition. Every food carries the server's Sharpit score (web ADR-063):
  a badge in lists, a line when it breaks a declared diet, and on the portion page the dial,
  the diet fit, what to watch, its strengths and the additives (`FoodHealthViews`); a search hit
  is completed by its barcode read when opened. Search results come ranked by name (web ADR-064).
  The coach opened from Nutrition carries the day's nutrition. MyFitnessPal is never
  linked from the iPhone (App Review 5.2.2, [ADR 0010](docs/adr/0010-import-the-myfitnesspal-export-instead-of-linking-it.md)):
  the athlete imports their own export file from Nutrition's « … » menu
- Activity detail: effort and feeling are rated in one drawer that saves on each tap
  (`ActivitySubjectiveStore`); compliance opens a drawer with the verdict in words
- ADRs specific to the native client: `docs/adr/`
- Spec / plan: `docs/superpowers/`

Native never calls `/api/presentation/*`. See SHARPIT ADR-040.

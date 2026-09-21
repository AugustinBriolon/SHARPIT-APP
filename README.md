# SHARPIT-APP

Native iPhone client for [SHARPIT](https://github.com/AugustinBriolon/SHARPIT) — Athlete Operating System.

## Requirements

- Xcode 27 / Swift 6 language mode
- iPhone simulator (prefer iOS 27 for Liquid Glass)
- Clerk Native API enabled; same publishable key as the web app
- An API origin: Debug builds use the sibling repo SHARPIT running locally
  (`docker compose up -d` then `yarn dev`, serving `http://127.0.0.1:3000`), Release builds
  use `https://sharpit.vercel.app` — see [Pointing at a server](#pointing-at-a-server)

## Signing

**Simulator.** Clerk requires Keychain, so simulator builds use **Sign to Run Locally**
(`CODE_SIGN_IDENTITY=-`). Fully unsigned apps crash at launch with OSStatus `-34018`.

**iPhone.** The app target supports `iphoneos`, and device builds sign with the Apple
Development identity of your team. The team is per machine, so it lives in the gitignored
`Config/Local.xcconfig`, next to the API origin:

```
SHARPIT_API_ORIGIN = https:/$()/sharpit.vercel.app
DEVELOPMENT_TEAM = <your team id>
```

Find the team id in Xcode → Settings → Accounts, or with
`defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier`. Then pick the phone as the
run destination and press Run. On the phone, enable Developer Mode (Settings → Privacy &
Security), and trust the developer under Settings → General → VPN & Device Management the
first time. A free Personal Team signs for 7 days.

WeatherKit, HealthKit and CloudKit are entitled and need a paid team; on a free Personal Team
the app still builds and runs, but the weather chip reads "Météo indisponible", Apple Health
cannot be enabled, and the cache stays device-local. Associated Domains is not entitled yet.

## Brand fonts

Syne, IBM Plex Sans and JetBrains Mono (all SIL OFL 1.1) carry most of the SHARPIT
identity. They are not committed yet:

```bash
./scripts/fetch-brand-fonts.sh
```

The files land in `SHARPIT-APP/Resources/Fonts` and `SharpitFonts.register()` picks up
whatever is in the bundle at launch — no Info.plist or project change needed. Until then
`SharpitTypography` falls back to the system face: the layout is right, the identity is not.

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
| Production on a phone or TestFlight | Release default, `https://sharpit.vercel.app` |
| Debug build against a deployed instance | `SHARPIT_API_ORIGIN = https:/$()/…` in `Config/Local.xcconfig` (gitignored) |
| Simulator against a preview, no rebuild | `SHARPIT_API_ORIGIN` in the scheme: Run → Arguments → Environment Variables |
| UI work, no server | use `FixtureTodayClient` |

`//` starts a comment in an xcconfig, so write the scheme's slashes as `https:/$()/host`.

## Build & test

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

## Architecture

- Auth: ClerkKit + ClerkKitUI (`AuthGate` → `AuthView` sheet)
- Shell: five tabs (Résumé / Plan / Coach / Activité / Moi)
- Résumé: `GET /api/v1/today` via `SharpitClient` + Bearer token from `clerk.auth.getToken()`.
  The server links the day's finished activities to their planned sessions on that read
  ([ADR-042](../SHARPIT/docs/adr/ADR-042-today-links-activities-on-read.md)); a session it
  missed can be linked by hand from the planned session's drawer.
- Coach: `/api/coach/chat` streams the answer; the conversation is kept server-side through
  `/api/coach/conversations`, and the history sheet lists, reopens and deletes them
- Sommeil / Récupération: drill-downs opened from the Today gauges, read from
  `/api/v1/sleep` and `/api/v1/recovery` (projections of the web's view models), with a day
  picker shared with Plan
- Freshness: Today starts a provider pull on launch, foreground and pull-to-refresh
  (`/api/v1/sync`), and Moi can switch on Apple Health as a gap-filling source, with a
  diagnostic of what Apple Health holds ([ADR 0005](docs/adr/0005-app-started-sync-and-apple-health.md))
- Journal: the day's signals via `/api/day-journal`, and what it asks for via
  `/api/journal-prefs`. Preferences round-trip as raw JSON so the keys the app does not
  render — diet flags, the nutrition panel, thresholds — survive a save from the phone.
  Sections follow when a signal happened (Journée, Checklist auto, Nuit dernière, Signaux du
  jour), and the automatic checklist is read from `/api/journal/day-signals` rather than
  recomputed — the thresholds and sport rules live on the web
- Activity status: the training mode (actif / en pause / blessé / malade) via
  `/api/activity-status`, written on every pick from Today's toolbar
- Moi: a grouped hub mirroring the web's Réglages — Modèle (Corps, Seuils & repères),
  Compte (Profil), Préférences (densité de lecture), Données (Garmin, Apple Santé,
  diagnostic), À propos. Profil and Seuils edit `/api/athlete-profile` through a partial
  PATCH that names only the fields the athlete changed; Corps reads `/api/body-composition`
  and is read-only, since a weigh-in is written by a scale
- Reading density: `displayMode` (essentiel / expert) read once into a `DisplayModeStore` in
  the environment. It chooses what is shown and how it is named, never what is measured;
  session load is visible in both readings, as « charge 78 » or « 78 TSS »
  ([ADR 0006](docs/adr/0006-reading-density-governs-the-technical-layer.md))
- Local cache: SwiftData snapshots of a day's Today and journal, so both screens paint before
  the network answers and offline. The server stays the source of truth — a write always goes
  to `/api` and the cache is written from its echo — and the cache replicates through the
  athlete's private iCloud
  ([ADR 0007](docs/adr/0007-icloud-replicates-the-read-cache-only.md))
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
- Activity detail: effort and feeling are rated in one drawer that saves on each tap
  (`ActivitySubjectiveStore`); compliance opens a drawer with the verdict in words
- ADRs specific to the native client: `docs/adr/`
- Spec / plan: `docs/superpowers/`

Native never calls `/api/presentation/*`. See SHARPIT ADR-040.

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
first time. A free Personal Team signs for 7 days. Associated Domains and WeatherKit need a
paid team and are not in the entitlements yet.

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
- Journal: the day's signals via `/api/day-journal`, and what it asks for via
  `/api/journal-prefs`. Preferences round-trip as raw JSON so the keys the app does not
  render — the web's automatic items, diet flags, thresholds — survive a save from the phone
- Activity status: the training mode (actif / en pause / blessé / malade) via
  `/api/activity-status`, written on every pick from Today's toolbar
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
- Semantic color, pressable tiles and the filled coach call to action
  ([ADR 0003](docs/adr/0003-semantic-color-and-a-filled-coach-call-to-action.md))
- Activity detail: effort and feeling are rated in one drawer that saves on each tap
  (`ActivitySubjectiveStore`); compliance opens a drawer with the verdict in words
- ADRs specific to the native client: `docs/adr/`
- Spec / plan: `docs/superpowers/`

Native never calls `/api/presentation/*`. See SHARPIT ADR-040.

# SHARPIT-APP

Native iPhone client for [SHARPIT](https://github.com/AugustinBriolon/SHARPIT) — Athlete Operating System.

## Requirements

- Xcode 27 / Swift 6 language mode
- iPhone simulator (prefer iOS 27 for Liquid Glass)
- Clerk Native API enabled; same publishable key as the web app
- An API origin: Debug builds use the sibling repo SHARPIT running locally
  (`docker compose up -d` then `yarn dev`, serving `http://127.0.0.1:3000`), Release builds
  use `https://sharpit.vercel.app` — see [Pointing at a server](#pointing-at-a-server)

## Signing (simulator)

Clerk requires Keychain. Builds use **Sign to Run Locally** (`CODE_SIGN_IDENTITY=-`, `CODE_SIGNING_ALLOWED=YES`). Fully unsigned apps crash at launch with OSStatus `-34018`.

Device installs, Associated Domains, and WeatherKit still need a personal Apple Development team (avoid on this managed Mac until signing works).

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
- Weather chip: WeatherKit + Core Location (not API weather)
- Design system: `SHARPIT-APP/DesignSystem/`. Colour and radius are **generated** from the
  web design system — edit `../SHARPIT/src/lib/brand/brand-tokens.ts` or
  `../SHARPIT/src/app/globals.css`, run `yarn tokens:ios` there, and commit the regenerated
  `SharpitTokens.generated.swift` ([ADR-041](../SHARPIT/docs/adr/ADR-041-ios-design-tokens-generated-from-web.md)).
  Spec: `docs/superpowers/specs/2026-09-16-ios-design-system-design.md` (tokens, typography
  and spacing sections superseded by ADR-041)
- Spec / plan: `docs/superpowers/`

Native never calls `/api/presentation/*`. See SHARPIT ADR-040.

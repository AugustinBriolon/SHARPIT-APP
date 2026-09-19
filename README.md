# SHARPIT-APP

Native iPhone client for [SHARPIT](https://github.com/AugustinBriolon/SHARPIT) — Athlete Operating System.

## Requirements

- Xcode 27 / Swift 6 language mode
- iPhone simulator (prefer iOS 27 for Liquid Glass)
- Clerk Native API enabled; same publishable key as the web app
- An API origin: either the sibling repo SHARPIT running locally (`docker compose up -d`
  then `yarn dev`, serving `http://127.0.0.1:3000`), or a deployed instance via the
  `SHARPIT_API_ORIGIN` environment variable — see [Pointing at a server](#pointing-at-a-server)

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

`APIConfiguration.baseURL` reads `SHARPIT_API_ORIGIN` from the environment before falling
back, so you can switch target without touching code. Set it in the scheme under
Run → Arguments → Environment Variables:

| Goal | Setting |
| --- | --- |
| Real data, no local stack | `SHARPIT_API_ORIGIN` = a deployed origin |
| Local full stack | leave unset (DEBUG defaults to `http://127.0.0.1:3000`) |
| UI work, no server | use `FixtureTodayClient` |

## Build & test

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

## Architecture

- Auth: ClerkKit + ClerkKitUI (`AuthGate` → `AuthView` sheet)
- Shell: five tabs (Résumé / Plan / Coach / Activité / Moi)
- Résumé: `GET /api/v1/today` via `SharpitClient` + Bearer token from `clerk.auth.getToken()`
- Weather chip: WeatherKit + Core Location (not API weather)
- Design system: `SHARPIT-APP/DesignSystem/`. Colour and radius are **generated** from the
  web design system — edit `../SHARPIT/src/lib/brand/brand-tokens.ts` or
  `../SHARPIT/src/app/globals.css`, run `yarn tokens:ios` there, and commit the regenerated
  `SharpitTokens.generated.swift` ([ADR-041](../SHARPIT/docs/adr/ADR-041-ios-design-tokens-generated-from-web.md)).
  Spec: `docs/superpowers/specs/2026-09-16-ios-design-system-design.md` (tokens, typography
  and spacing sections superseded by ADR-041)
- Spec / plan: `docs/superpowers/`

Native never calls `/api/presentation/*`. See SHARPIT ADR-040.

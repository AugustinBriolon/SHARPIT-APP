# SHARPIT-APP

Native iPhone client for [SHARPIT](https://github.com/AugustinBriolon/SHARPIT) — Athlete Operating System.

## Requirements

- Xcode 27 / Swift 6 language mode
- iPhone simulator (prefer iOS 27 for Liquid Glass)
- Clerk Native API enabled; same publishable key as the web app
- Local API: sibling repo SHARPIT with `yarn dev` on `http://127.0.0.1:3000`

## Build & test

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' test
```

Simulator-only unsigned builds are configured for this managed Mac (`CODE_SIGNING_ALLOWED=NO`). Device / WeatherKit entitlement needs a personal team on a non-managed machine.

## Architecture

- Auth: ClerkKit + ClerkKitUI (`AuthGate` → `AuthView` sheet)
- Shell: five tabs (Résumé / Plan / Coach / Activité / Moi)
- Résumé: `GET /api/v1/today` via `SharpitClient` + Bearer token from `clerk.auth.getToken()`
- Weather chip: WeatherKit + Core Location (not API weather)
- Spec / plan: `docs/superpowers/`

Native never calls `/api/presentation/*`. See SHARPIT ADR-040.

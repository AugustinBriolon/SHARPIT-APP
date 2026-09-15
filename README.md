# SHARPIT-APP

Native iPhone client for [SHARPIT](https://github.com/AugustinBriolon/SHARPIT) — Athlete Operating System.

## Requirements

- Xcode 27 / Swift 6 language mode
- iPhone simulator (prefer iOS 27 for Liquid Glass)
- Clerk Native API enabled; same publishable key as the web app
- Local API: sibling repo SHARPIT with `yarn dev` on `http://127.0.0.1:3000`

## Signing (simulator)

Clerk requires Keychain. Builds use **Sign to Run Locally** (`CODE_SIGN_IDENTITY=-`, `CODE_SIGNING_ALLOWED=YES`). Fully unsigned apps crash at launch with OSStatus `-34018`.

Device installs, Associated Domains, and WeatherKit still need a personal Apple Development team (avoid on this managed Mac until signing works).

## Build & test

## Architecture

- Auth: ClerkKit + ClerkKitUI (`AuthGate` → `AuthView` sheet)
- Shell: five tabs (Résumé / Plan / Coach / Activité / Moi)
- Résumé: `GET /api/v1/today` via `SharpitClient` + Bearer token from `clerk.auth.getToken()`
- Weather chip: WeatherKit + Core Location (not API weather)
- Spec / plan: `docs/superpowers/`

Native never calls `/api/presentation/*`. See SHARPIT ADR-040.

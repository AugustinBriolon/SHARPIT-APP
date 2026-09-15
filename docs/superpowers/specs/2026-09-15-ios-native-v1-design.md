# SHARPIT iOS native v1 — design

**Date:** 2026-09-15  
**Status:** Draft for review  
**Repos:** `SHARPIT-APP` (iOS product) · `SHARPIT` (API + complementary web)

## 1. Product decision

iOS is the product. The existing Next.js app remains a complementary client (desktop density, OAuth for Garmin/Strava, Expert mode, onboarding). One Core, one canonical HTTP contract, two UIs.

v1 ships a usable iPhone app: Clerk auth, five-tab shell, **Résumé (Today) read-only**. HealthKit, widgets, Watch, push, offline cache, and Today writes are out of scope.

The complementary web keeps `/api/presentation/*` unchanged. iOS never calls those routes.

## 2. Architecture

```
Integrations (Garmin, Strava, …)
        │
 Core + Digital Twin          (TypeScript, repo SHARPIT — never in Swift)
        │
 Canonical API /api/v1        (versioned, client-agnostic JSON)
        │
   ┌────┴────┐
  iOS        Web
 (product)  (complement)
```

- Backend stays Next.js + Neon + Clerk. No second service.
- `GET /api/v1/today` is a **projection** of `buildTodayPresentationViewModel`. It does not republish `TodayViewModel` (no Tailwind classes, no Next.js `href`s).
- `getCurrentAthleteId` / `auth()` remain the identity path. Native clients send `Authorization: Bearer <Clerk session JWT>`. `clerkMiddleware` in `src/proxy.ts` already calls `auth.protect()` on non-public routes; Clerk reads the Bearer header. No CORS change is required: `URLSession` is not a browser.
- v1 iOS assumes the athlete already has a web account and connected integrations. Empty states send the athlete to the complementary web.

## 3. Canonical contract — `GET /api/v1/today`

**Request**

- Query: `trainingDayId` (required, `YYYY-MM-DD`, athlete-local calendar day computed on device).
- Header: `Authorization: Bearer <token>` (required in production). Dev may use existing `DEV_BYPASS_CLERK` like other APIs.

**Response 200** — JSON only, `Content-Type: application/json`.

```json
{
  "apiVersion": 1,
  "trainingDayId": "2026-09-15",
  "empty": null,
  "verdict": {
    "eyebrow": "string",
    "headline": "string",
    "subline": "string",
    "posture": "protect",
    "confidencePct": 72,
    "limitingCause": "string or null"
  },
  "weather": { "city": "string", "tempC": 12, "condition": "string" },
  "sessions": [
    {
      "id": "string",
      "kind": "planned",
      "title": "string",
      "subtitle": "string or null",
      "metrics": [{ "label": "string", "value": "string", "unit": "string" }]
    }
  ],
  "signals": [
    { "key": "sleep", "score": "string", "caption": "string or null" }
  ]
}
```

**Field rules**

| Field | Source | Notes |
| --- | --- | --- |
| `apiVersion` | constant `1` | Bump only on breaking change. |
| `empty` | `vm.emptyState` or `!vm.hasContent` | `null` when the screen can render. Otherwise `{ title, message, code: "NO_CONTENT", webURL }`. `webURL` is an absolute complementary-web URL (web origin + existing `emptyState.action.href` when present, else origin `/`). If `empty` is non-null, iOS shows only the empty UI and ignores `verdict`. |
| `verdict` | `vm.hero` + `twinTrustStrip` | Required even when `empty` is set (keeps decoding simple). `posture` ∈ `protect \| steady \| push \| uncertain`. `confidencePct` from `confidencePctRounded`. `limitingCause` from `limitingCauseText`. When `empty` is set, `headline` may repeat `empty.title`. |
| `weather` | `vm.header.weather` | `null` when missing. Drop `locationKnown`. |
| `sessions` | `vm.actionRow.daySummaryLines` | `kind`: `planned` \| `done`. Drop `href`. Metrics max 3, already capped server-side. |
| `signals` | `vm.hero.signalPreviews` | `key` ∈ `sleep \| recovery \| effort \| adaptation`. `score` = `scoreDisplay`. `caption` = `subtitle`. No gauge/spark visuals. |

**Errors**

| Status | When | Body |
| --- | --- | --- |
| 400 | missing/invalid `trainingDayId` | `{ "error": "..." }` |
| 401 | no Clerk session | `{ "error": "..." }` |
| 500 | projection/build failure | `{ "error": "Impossible de produire la vue Today" }` |

**Writes.** Not in v1. Morning recalibration, check-in, session linking stay on the web. If the view-model contains an open proposal, v1 does **not** surface a confirm CTA. Copy already in `verdict.subline` / session titles is enough.

**Web origin** used to build `empty.webURL`: env `NEXT_PUBLIC_APP_URL` if set, else request origin.

## 4. iOS screen — Résumé

- `TabView`: Résumé · Plan · Coach · Activité · Moi. Only Résumé is real.
- Large navigation title: localized formatted `trainingDayId`.
- Pull-to-refresh re-fetches `/api/v1/today`.
- Order: verdict → sessions → signals. Weather only if payload non-null.
- Copy is **server-owned** (French). The app does not rewrite headlines.
- Native chrome: system type, Dynamic Type, 44 pt targets, safe area. No web plate/gauge clone.

**States**

| State | UI |
| --- | --- |
| Loading (no data) | Redacted placeholders, not a full-screen spinner. |
| Loaded | Sections above. |
| Empty `NO_CONTENT` | Title + message + button opening `webURL` in Safari (`SFSafariViewController` or `openURL`). |
| 401 | Signed-out Clerk UI (not a custom error page). |
| Transport failure | Inline banner + retry. No IndexedDB-style offline cache. |
| Placeholders | Plan / Coach / Activité / Moi: one-line “Bientôt”. |

## 5. Swift feasibility (compile gates)

The current Xcode project is a **Playgrounds multi-platform stub** (`import Playgrounds`, macOS + visionOS, App Sandbox, placeholder bundle id, no test target). Dumping Clerk + networking + UI on top of it will not compile cleanly. Implementation **must** pass these gates in order. Do not start the next gate until `xcodebuild` is green.

```bash
xcodebuild -scheme SHARPIT-APP -destination 'generic/platform=iOS Simulator' build
```

### Known hazards

1. **Playgrounds template** — `import Playgrounds` and `#Playground` are not an iOS app. Remove them before any feature code.
2. **Multi-platform settings** — `SUPPORTED_PLATFORMS` includes `macosx` and `xros`; `ENABLE_APP_SANDBOX = YES` is a Mac setting that fights outbound networking. v1 is **iPhone only**: `iphoneos` + `iphonesimulator`, `TARGETED_DEVICE_FAMILY = 1`, App Sandbox off.
3. **Language mode vs compiler.** The stub has `SWIFT_VERSION = 5.0` because that is still Xcode’s new-project default, not because Swift 5 is current. This machine compiles with **Apple Swift 6.4** (Xcode 27). There is no Swift 7 language mode to select yet — Swift 7 is a set of upcoming features (`enabled_in: 7`). v1 uses **Swift 6 language mode** (`SWIFT_VERSION = 6`), keeps Approachable Concurrency + default MainActor isolation (already on), and keeps the Swift 7 upcoming flags the stub already set (`MemberImportVisibility`). Isolation errors are handled by the actor/`String`-token pattern, not by staying on language mode 5.
4. **Clerk + isolation** — never put `Clerk.shared` inside a background actor. Obtain the JWT on the main actor, pass a `String` into networking.
5. **Clerk Native API** — Dashboard must have Native API enabled, and this iOS app registered (App ID prefix + bundle id). Without that, the app compiles but auth fails at runtime. Associated Domains `webcredentials:{frontend-api-host}` is a v1 Clerk prerequisite, not a later nice-to-have.
6. **Local API** — Simulator can hit `http://127.0.0.1:3000`. Physical device cannot. Debug `Info.plist` allows arbitrary loads / local networking **for Debug only**. Production uses HTTPS.

### Gate 0 — iPhone Hello World

Convert the stub into a compiling iPhone SwiftUI app: rename `@main` to `SharpitApp`, delete Playgrounds, restrict platforms, set bundle id `app.sharpit.ios`. One `Text` on screen. **Stop and compile.**

### Gate 1 — Test target

Add a Swift Testing target (`SHARPIT-APPTests`). One `@Test` that asserts `1 + 1 == 2`. **Stop and compile** (`xcodebuild test` or at least build the test target).

### Gate 2 — Clerk SPM, no UI yet

Add `https://github.com/clerk/clerk-ios` (up-to-next-major from latest 1.x). Link `ClerkKit` + `ClerkKitUI`. `Clerk.configure(publishableKey:)` in `SharpitApp.init`, inject `.environment(Clerk.shared)`. Signed-out vs signed-in branch with `AuthView` in a sheet (prebuilt). **Stop and compile.** Dashboard Native API + bundle registration happen here or the next run is a runtime fail, not a compile fail.

### Gate 3 — DTOs + decoding tests (no network)

`V1TodayResponse` and nested types: `struct`, `Codable`, `Sendable`, `Equatable`. Enums are `String` raw values. No UIKit, no Clerk in this module. Tests decode three fixtures: full hero, empty `NO_CONTENT`, null weather / empty sessions. **Stop and compile tests.**

### Gate 4 — `actor APIClient` + fixture UI

```
MainActor (views, Clerk.getToken)
    → actor SharpitClient (URLSession)
        → V1TodayResponse
```

Protocol `TodayServing` so tests inject a fixture without URLSession. Today screen renders the fixture. **Stop and compile.**

### Gate 5 — Live `GET /api/v1/today`

Only after the web projection exists and Gate 4 is green.

If a gate fails twice on the same class of error (isolation, SPM, signing), stop and fix that class; do not add files.

### Isolation pattern (mandatory)

```swift
// View / ViewModel — MainActor (project default)
let token = try await clerk.auth.getToken()
let day = TrainingDayId.today(in: .current)
let payload = try await client.today(trainingDayId: day, token: token)
```

`SharpitClient` is an `actor`. Token is `String`. DTOs do not import Clerk.

## 6. iOS project layout

```
SHARPIT-APP/
  App/SharpitApp.swift
  App/RootView.swift              // auth gate + TabView
  Auth/AuthSession.swift          // signed-in check only
  Features/Today/TodayView.swift
  Features/Today/TodayModel.swift // maps V1TodayResponse → screen state
  Features/Shell/PlaceholderTab.swift
  Networking/SharpitClient.swift  // actor
  Networking/V1Today.swift        // DTOs
  Networking/APIConfiguration.swift
  Resources/Assets.xcassets
```

No business logic in views. No `URLSession` in views. No Core/Twin types in Swift.

**Configuration**

- `APIConfiguration.baseURL`: Debug `http://127.0.0.1:3000`, Release the production web origin (same host the complementary web already uses).
- Clerk publishable key: wired in `Clerk.configure` at implementation time (value supplied by the developer, same key as the web app). Do not invent a second Clerk application.
- Bundle id: `app.sharpit.ios` (change only if Apple Developer team requires it).

**Auth UX:** Clerk prebuilt — `UserButton(signedOutContent:)` + `AuthView()` in a sheet. Combined sign-in/sign-up. Sign in with Apple only if Clerk environment has Apple enabled (then add the capability). No custom auth screens.

## 7. Web repo changes (SHARPIT)

| Change | Why |
| --- | --- |
| `src/lib/presentation/v1/today.ts` | Pure projection `TodayViewModel → V1TodayResponse`. No `NextRequest`. |
| `src/app/api/v1/today/route.ts` | Auth via `getCurrentAthleteId`, validate `trainingDayId`, call existing builder, project, return JSON. |
| Tests on the projector | Hero, empty, null weather, four signal keys, no `href` / no `bgClass` in output. |
| Route test | 400 without date; 200 shape `{ apiVersion: 1 }`. |
| ADR | iOS is the product; `/api/v1` is the canonical contract; web presentation routes stay for the complementary UI. |
| `src/proxy.ts` | No special case if `auth.protect()` already covers `/api/v1/*`. Do not add `/api/v1` to `isPublicRoute`. |

Do not modify `src/app/api/presentation/today/route.ts`.

## 8. Testing

| Layer | What |
| --- | --- |
| Web unit | Projector: golden fixtures from a minimal `TodayViewModel`. |
| Web route | Invalid date → 400; mocked builder → 200. |
| iOS unit | Decode JSON fixtures checked into `SHARPIT-APPTests/Fixtures/` (same payloads as the web projector tests, duplicated — the repos are not a monorepo). |
| iOS unit | `TodayModel` mapping: empty vs main vs missing weather. |
| Manual | Simulator: sign in, Résumé against local `yarn dev`, pull-to-refresh, signed-out sheet. |

No E2E / UI snapshot in v1. No iOS test that hits the live network in CI.

## 9. Out of scope (v1)

HealthKit, WidgetKit, Watch, push, Live Activities, offline snapshot, Today POST endpoints, drill-downs, Plan / Coach / Activité / Moi implementations, migrating the web UI onto `/api/v1`, native onboarding, native OAuth.

## 10. Implementation order

Two repos, this sequence:

1. Gate 0–1 in `SHARPIT-APP` (compiling iPhone app + tests).
2. Projector + `GET /api/v1/today` in `SHARPIT` (Vitest green).
3. Gate 2 Clerk (compile + Dashboard Native API).
4. Gate 3–4 DTOs, actor client, fixture UI.
5. Gate 5 live fetch.
6. ADR + README notes in both repos.

## 11. Explicit choices (no placeholders)

- Approach: canonical `/api/v1`, not `/api/presentation/*`, not a device-side Twin.
- v1 writes: none.
- CORS: not applicable to native `URLSession`.
- Offline: none.
- iOS: Swift **6 language mode** on the Swift **6.4** compiler (Xcode 27). Enable Swift 7 upcoming features already present in the stub; do not wait for a Swift 7 language mode. Deployment target: iOS 18, unless the stub refuses — then keep the SDK default and record it in the ADR.
- Tab placeholders: visible, labelled “Bientôt”, not hidden.
- Complementary web empty CTA: Safari to `empty.webURL`.

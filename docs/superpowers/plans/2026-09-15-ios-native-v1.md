# SHARPIT iOS native v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a compiling iPhone app that signs in with Clerk and renders read-only Résumé from canonical `GET /api/v1/today`, while the Next.js app stays the complementary web client.

**Architecture:** Core and Twin stay in the SHARPIT TypeScript repo. A pure projector maps `TodayViewModel` → versioned JSON. The iOS app is a SwiftUI client: Clerk on the main actor, `actor SharpitClient` for HTTP, DTOs with no Clerk import.

**Tech Stack:** Swift 6 language mode (compiler 6.4 / Xcode 27), SwiftUI, Swift Testing, ClerkKit + ClerkKitUI, Next.js route handlers, Vitest.

## Global Constraints

- Two git repos: `/Users/H6245/Documents/DEV/PERSO/SHARPIT-APP` (iOS product) and `/Users/H6245/Documents/DEV/PERSO/SHARPIT` (API + complementary web). Commit in the repo that owns the files. Never `git add` across repos in one commit.
- Spec: `SHARPIT-APP/docs/superpowers/specs/2026-09-15-ios-native-v1-design.md`
- Compile gate: do not start the next iOS task until `xcodebuild -scheme SHARPIT-APP -destination 'generic/platform=iOS Simulator' build` exits 0.
- iPhone only: `iphoneos` + `iphonesimulator`, `TARGETED_DEVICE_FAMILY = 1`, App Sandbox off, no Playgrounds, no macOS/visionOS.
- `SWIFT_VERSION = 6`. Keep `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`.
- Bundle id: `app.sharpit.ios`. Display name: SHARPIT.
- iOS never calls `/api/presentation/*`. v1 Today is GET-only. No HealthKit, widgets, Watch, push, offline cache.
- Isolation: `clerk.auth.getToken()` on the main actor; pass `String` into `actor SharpitClient`. DTOs do not import Clerk.
- Copy on Résumé is server-owned (French). Placeholders for Plan/Coach/Activité/Moi: « Bientôt ».
- If the same compile-error class happens twice, stop adding files and fix that class.

## File map

**SHARPIT-APP**

| Path | Responsibility |
| --- | --- |
| `SHARPIT-APP/App/SharpitApp.swift` | `@main`, Clerk configure, environment |
| `SHARPIT-APP/App/RootView.swift` | Auth gate + `TabView` |
| `SHARPIT-APP/Auth/AuthGate.swift` | Signed-out sheet vs signed-in shell |
| `SHARPIT-APP/Features/Shell/PlaceholderTab.swift` | Bientôt tabs |
| `SHARPIT-APP/Features/Today/TodayView.swift` | Résumé UI |
| `SHARPIT-APP/Features/Today/TodayModel.swift` | `V1TodayResponse` → screen state |
| `SHARPIT-APP/Networking/V1Today.swift` | Codable DTOs |
| `SHARPIT-APP/Networking/APIConfiguration.swift` | Base URL |
| `SHARPIT-APP/Networking/SharpitClient.swift` | `actor` + `TodayServing` |
| `SHARPIT-APP/Info.plist` | ATS local networking (simulator → localhost) |
| `SHARPIT-APPTests/V1TodayDecodingTests.swift` | Fixture decode |
| `SHARPIT-APPTests/TodayModelTests.swift` | Empty vs main mapping |
| `SHARPIT-APPTests/Fixtures/*.json` | Same payloads as web projector tests |

**SHARPIT**

| Path | Responsibility |
| --- | --- |
| `src/lib/presentation/v1/today.ts` | Pure projector |
| `src/lib/presentation/v1/today.test.ts` | Projector unit tests |
| `src/app/api/v1/today/route.ts` | HTTP |
| `src/app/api/v1/today/route.test.ts` | 400 / 200 |
| `docs/adr/ADR-040-canonical-v1-api-ios-product.md` | Product/API decision |
| README Modules row for `/api/v1` | Discoverability |

Do not modify `src/app/api/presentation/today/route.ts` or `src/proxy.ts` unless `auth.protect()` is proven to block Bearer (it must not; Clerk already reads the header).

---

### Task 1: Gate 0 — iPhone Hello World

**Repo:** `SHARPIT-APP`

**Files:**
- Delete: `SHARPIT-APP/ContentView.swift`, `SHARPIT-APP/MyApp.swift`
- Create: `SHARPIT-APP/App/SharpitApp.swift`
- Modify: `SHARPIT-APP.xcodeproj/project.pbxproj` (platform, sandbox, bundle id, Swift 6)

**Interfaces:**
- Consumes: nothing
- Produces: compiling `@main struct SharpitApp`

- [ ] **Step 1: Replace the Playgrounds entry point**

Create `SHARPIT-APP/App/SharpitApp.swift`:

```swift
import SwiftUI

@main
struct SharpitApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SHARPIT")
        }
    }
}
```

Delete `SHARPIT-APP/MyApp.swift` and `SHARPIT-APP/ContentView.swift` (they import Playgrounds).

- [ ] **Step 2: Restrict the target to iPhone and Swift 6**

In both Debug and Release target build settings (`000000000000000111000000` and `000000000000000112000000`):

- `PRODUCT_BUNDLE_IDENTIFIER = app.sharpit.ios;`
- `PRODUCT_NAME = SHARPIT;` (keep `$(TARGET_NAME)` if renaming the product is noisy; then set `INFOPLIST_KEY_CFBundleDisplayName = SHARPIT;`)
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";`
- `TARGETED_DEVICE_FAMILY = 1;`
- `ENABLE_APP_SANDBOX = NO;`
- `SWIFT_VERSION = 6;`
- `IPHONEOS_DEPLOYMENT_TARGET = 18.0;` at project level if the stub allows it; if `xcodebuild` fails, leave the stub’s 27.0 and note it in ADR-040.

Remove `macosx` / `xros` from `SUPPORTED_PLATFORMS`. Do not add files to `pbxproj` by hand — the synchronized root group already picks up `App/`.

- [ ] **Step 3: Compile**

Run from `SHARPIT-APP`:

```bash
xcodebuild -scheme SHARPIT-APP -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`. If the scheme is still named `MyApp`, use that name or create `xcshareddata/xcschemes/SHARPIT-APP.xcscheme` that points at target `SHARPIT-APP`.

- [ ] **Step 4: Commit (this repo only)**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT-APP
git add SHARPIT-APP/App/SharpitApp.swift SHARPIT-APP.xcodeproj/project.pbxproj
git add -u SHARPIT-APP/MyApp.swift SHARPIT-APP/ContentView.swift
git commit -m "$(cat <<'EOF'
build: convert playgrounds stub into an iPhone Swift 6 app

EOF
)"
```

---

### Task 2: Gate 1 — Swift Testing target

**Repo:** `SHARPIT-APP`

**Files:**
- Create: `SHARPIT-APPTests/SmokeTests.swift`
- Modify: `SHARPIT-APP.xcodeproj/project.pbxproj` (unit-test target + synchronized tests group)
- Create: `SHARPIT-APP.xcodeproj/xcshareddata/xcschemes/SHARPIT-APP.xcscheme` if missing, with a TestAction that includes `SHARPIT-APPTests`

**Interfaces:**
- Consumes: Task 1 app target
- Produces: `SHARPIT-APPTests` bundle hosted by `SHARPIT-APP.app`

- [ ] **Step 1: Write the first test**

`SHARPIT-APPTests/SmokeTests.swift`:

```swift
import Testing

@Test func smoke() {
    #expect(1 + 1 == 2)
}
```

- [ ] **Step 2: Add the unit-test target**

Add a `PBXNativeTarget` `SHARPIT-APPTests` (`productType = com.apple.product-type.bundle.unit-test`) with a `PBXFileSystemSynchronizedRootGroup` path `SHARPIT-APPTests`. Build settings:

- `GENERATE_INFOPLIST_FILE = YES;`
- `BUNDLE_LOADER = "$(TEST_HOST)";`
- `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SHARPIT-APP.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SHARPIT-APP";`
- `SWIFT_VERSION = 6;`
- `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";`
- `IPHONEOS_DEPLOYMENT_TARGET` same as the app
- `TEST_TARGET_NAME = SHARPIT-APP;` (if using Swift Testing in-process; otherwise host the app)

Wire the test target into the shared scheme’s `TestAction`. Prefer creating the target with Xcode’s “Unit Testing Bundle” if hand-editing `pbxproj` fails once — then re-apply Swift 6 / iPhone-only settings. Do not retry a broken `pbxproj` more than twice.

- [ ] **Step 3: Run tests**

```bash
xcodebuild -scheme SHARPIT-APP -destination 'generic/platform=iOS Simulator' test
```

Expected: `** TEST SUCCEEDED **` and `smoke` passed. `test` also implies `build` is still green.

- [ ] **Step 4: Commit**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT-APP
git add SHARPIT-APPTests SHARPIT-APP.xcodeproj
git commit -m "$(cat <<'EOF'
test: add Swift Testing target smoke test

EOF
)"
```

---

### Task 3: Projector `TodayViewModel` → v1 JSON

**Repo:** `SHARPIT`

**Files:**
- Create: `src/lib/presentation/v1/today.ts`
- Test: `src/lib/presentation/v1/today.test.ts`

**Interfaces:**
- Consumes: `TodayViewModel` field subset (structural)
- Produces: `projectV1Today(source, { trainingDayId, webOrigin }) → V1TodayResponse`

- [ ] **Step 1: Write failing tests**

`src/lib/presentation/v1/today.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { projectV1Today, type V1TodaySource } from './today';

const origin = 'https://app.example';

function source(over: Partial<V1TodaySource> & { hero?: Partial<V1TodaySource['hero']> }): V1TodaySource {
  return {
    hasContent: true,
    emptyState: null,
    hero: {
      eyebrow: 'Ce matin',
      headline: 'Séance prévue',
      subline: 'Tenir',
      posture: 'steady',
      twinTrustStrip: { confidencePctRounded: 72, limitingCauseText: 'Sommeil court' },
      signalPreviews: [
        { key: 'sleep', scoreDisplay: '78', subtitle: 'Correct' },
        { key: 'recovery', scoreDisplay: '61', subtitle: null },
        { key: 'effort', scoreDisplay: '—', subtitle: null },
        { key: 'adaptation', scoreDisplay: '55', subtitle: null },
      ],
      ...over.hero,
    },
    header: { weather: { city: 'Lyon', tempC: 12, condition: 'Nuageux' } },
    actionRow: {
      daySummaryLines: [
        {
          id: 's1',
          kind: 'planned',
          primary: 'Seuil 40 min',
          secondary: 'Course',
          metrics: [{ label: 'Durée', value: '40', unit: 'min' }],
        },
      ],
    },
    ...over,
  };
}

describe('projectV1Today', () => {
  it('projects a full hero without href or Tailwind classes', () => {
    const json = projectV1Today(source({}), { trainingDayId: '2026-09-15', webOrigin: origin });
    expect(json.apiVersion).toBe(1);
    expect(json.trainingDayId).toBe('2026-09-15');
    expect(json.empty).toBeNull();
    expect(json.verdict).toEqual({
      eyebrow: 'Ce matin',
      headline: 'Séance prévue',
      subline: 'Tenir',
      posture: 'steady',
      confidencePct: 72,
      limitingCause: 'Sommeil court',
    });
    expect(json.weather).toEqual({ city: 'Lyon', tempC: 12, condition: 'Nuageux' });
    expect(json.sessions).toEqual([
      {
        id: 's1',
        kind: 'planned',
        title: 'Seuil 40 min',
        subtitle: 'Course',
        metrics: [{ label: 'Durée', value: '40', unit: 'min' }],
      },
    ]);
    expect(json.signals).toHaveLength(4);
    expect(JSON.stringify(json)).not.toMatch(/href|bgClass|rounded-/);
  });

  it('sets empty NO_CONTENT and absolute webURL', () => {
    const json = projectV1Today(
      source({
        hasContent: false,
        emptyState: {
          title: 'Pas encore de données',
          description: 'Connecte Garmin sur le web',
          action: { label: 'Ouvrir', href: '/moi' },
        },
      }),
      { trainingDayId: '2026-09-15', webOrigin: origin },
    );
    expect(json.empty).toEqual({
      title: 'Pas encore de données',
      message: 'Connecte Garmin sur le web',
      code: 'NO_CONTENT',
      webURL: 'https://app.example/moi',
    });
    expect(json.verdict.headline).toBe('Pas encore de données');
  });

  it('drops weather and sessions when absent', () => {
    const json = projectV1Today(
      source({ header: { weather: null }, actionRow: { daySummaryLines: [] } }),
      { trainingDayId: '2026-09-15', webOrigin: origin },
    );
    expect(json.weather).toBeNull();
    expect(json.sessions).toEqual([]);
  });
});
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT
yarn test src/lib/presentation/v1/today.test.ts
```

Expected: FAIL (module not found).

- [ ] **Step 3: Implement the projector**

`src/lib/presentation/v1/today.ts`:

```ts
import type { PresentationEmptyState } from '@/core/presentation/types';
import type { TodayViewModel } from '@/core/presentation/today-view-model';

export type V1TodaySource = {
  hasContent: boolean;
  emptyState: PresentationEmptyState | null;
  hero: {
    eyebrow: string;
    headline: string;
    subline: string;
    posture: 'protect' | 'steady' | 'push' | 'uncertain';
    twinTrustStrip: {
      confidencePctRounded: number | null;
      limitingCauseText: string | null;
    };
    signalPreviews: Array<{
      key: 'sleep' | 'recovery' | 'adaptation' | 'effort';
      scoreDisplay: string;
      subtitle: string | null;
    }>;
  };
  header: {
    weather: { city: string; tempC: number; condition: string } | null;
  };
  actionRow: {
    daySummaryLines: Array<{
      id: string;
      kind: 'done' | 'planned';
      primary: string;
      secondary?: string | null;
      metrics?: Array<{ label: string; value: string; unit: string }> | null;
    }>;
  };
};

export type V1TodayResponse = {
  apiVersion: 1;
  trainingDayId: string;
  empty: {
    title: string;
    message: string | null;
    code: 'NO_CONTENT';
    webURL: string;
  } | null;
  verdict: {
    eyebrow: string;
    headline: string;
    subline: string;
    posture: 'protect' | 'steady' | 'push' | 'uncertain';
    confidencePct: number | null;
    limitingCause: string | null;
  };
  weather: { city: string; tempC: number; condition: string } | null;
  sessions: Array<{
    id: string;
    kind: 'planned' | 'done';
    title: string;
    subtitle: string | null;
    metrics: Array<{ label: string; value: string; unit: string }>;
  }>;
  signals: Array<{
    key: 'sleep' | 'recovery' | 'effort' | 'adaptation';
    score: string;
    caption: string | null;
  }>;
};

function joinWebURL(webOrigin: string, href: string | undefined): string {
  const base = webOrigin.replace(/\/$/, '');
  if (!href || href === '/') return `${base}/`;
  if (href.startsWith('http://') || href.startsWith('https://')) return href;
  return `${base}${href.startsWith('/') ? href : `/${href}`}`;
}

export function projectV1Today(
  source: V1TodaySource,
  input: { trainingDayId: string; webOrigin: string },
): V1TodayResponse {
  const isEmpty = !source.hasContent || source.emptyState !== null;
  const emptyState = source.emptyState;
  const empty = isEmpty
    ? {
        title: emptyState?.title ?? 'Pas encore de données',
        message: emptyState?.description ?? null,
        code: 'NO_CONTENT' as const,
        webURL: joinWebURL(input.webOrigin, emptyState?.action?.href),
      }
    : null;

  return {
    apiVersion: 1,
    trainingDayId: input.trainingDayId,
    empty,
    verdict: {
      eyebrow: source.hero.eyebrow,
      headline: empty ? empty.title : source.hero.headline,
      subline: source.hero.subline,
      posture: source.hero.posture,
      confidencePct: source.hero.twinTrustStrip.confidencePctRounded,
      limitingCause: source.hero.twinTrustStrip.limitingCauseText,
    },
    weather: source.header.weather,
    sessions: source.actionRow.daySummaryLines.map((line) => ({
      id: line.id,
      kind: line.kind,
      title: line.primary,
      subtitle: line.secondary ?? null,
      metrics: line.metrics ?? [],
    })),
    signals: source.hero.signalPreviews.map((signal) => ({
      key: signal.key,
      score: signal.scoreDisplay,
      caption: signal.subtitle,
    })),
  };
}

export function projectV1TodayFromViewModel(
  vm: TodayViewModel,
  input: { trainingDayId: string; webOrigin: string },
): V1TodayResponse {
  return projectV1Today(vm, input);
}
```

Confirm `TodayViewModel` is assignable to `V1TodaySource` (`yarn typecheck`). If `signalPreviews` extra fields block assignability, the function parameter stays `V1TodaySource` and the route passes `vm` (structural typing should succeed).

- [ ] **Step 4: Run tests — expect PASS**

```bash
yarn test src/lib/presentation/v1/today.test.ts
```

- [ ] **Step 5: Commit**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT
git add src/lib/presentation/v1/today.ts src/lib/presentation/v1/today.test.ts
git commit -m "$(cat <<'EOF'
feat: project Today view-model into canonical v1 JSON

EOF
)"
```

Copy the three expected JSON objects from these tests into `SHARPIT-APP/SHARPIT-APPTests/Fixtures/` in Task 7 (`full.json`, `empty.json`, `sparse.json`). Duplicate on purpose (two repos).

---

### Task 4: `GET /api/v1/today`

**Repo:** `SHARPIT`

**Files:**
- Create: `src/app/api/v1/today/route.ts`
- Test: `src/app/api/v1/today/route.test.ts`

**Interfaces:**
- Consumes: `getCurrentAthleteId`, `buildTodayPresentationViewModel`, `getMorningRecalibrationPresentation`, `projectV1TodayFromViewModel`
- Produces: `GET` handler returning `V1TodayResponse`

- [ ] **Step 1: Write failing route tests**

Mirror `src/app/api/presentation/today/route.test.ts`: mock athlete, morning recalibration, builder. Assert:

1. Missing `trainingDayId` → 400, body `{ error: 'trainingDayId est requis et doit être au format YYYY-MM-DD' }`
2. Mocked builder → 200, `body.apiVersion === 1`, no `body.viewModel`

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { NextRequest } from 'next/server';

vi.mock('@/lib/auth/current-athlete', () => ({
  getCurrentAthleteId: vi.fn().mockResolvedValue('athlete-1'),
}));
vi.mock('@/lib/morning-recalibration/service', () => ({
  getMorningRecalibrationPresentation: vi.fn().mockResolvedValue(null),
}));
vi.mock('@/lib/presentation/today/today', () => ({
  buildTodayPresentationViewModel: vi.fn(),
}));
vi.mock('@/lib/presentation/v1/today', () => ({
  projectV1TodayFromViewModel: vi.fn().mockReturnValue({
    apiVersion: 1,
    trainingDayId: '2026-09-10',
    empty: null,
    verdict: {
      eyebrow: '',
      headline: 'ok',
      subline: '',
      posture: 'steady',
      confidencePct: null,
      limitingCause: null,
    },
    weather: null,
    sessions: [],
    signals: [],
  }),
}));

describe('GET /api/v1/today', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('rejects a missing trainingDayId', async () => {
    const { GET } = await import('./route');
    const response = await GET(new NextRequest('http://localhost/api/v1/today'));
    expect(response.status).toBe(400);
  });

  it('returns projected v1 JSON, not viewModel', async () => {
    const { buildTodayPresentationViewModel } = await import('@/lib/presentation/today/today');
    vi.mocked(buildTodayPresentationViewModel).mockResolvedValue({} as never);
    const { GET } = await import('./route');
    const response = await GET(
      new NextRequest('http://localhost/api/v1/today?trainingDayId=2026-09-10'),
    );
    const body = await response.json();
    expect(response.status).toBe(200);
    expect(body.apiVersion).toBe(1);
    expect(body.viewModel).toBeUndefined();
  });
});
```

Resolve `webOrigin`: `process.env.NEXT_PUBLIC_APP_URL` if set, else `request.nextUrl.origin`.

- [ ] **Step 2: Run — expect FAIL**

```bash
yarn test src/app/api/v1/today/route.test.ts
```

- [ ] **Step 3: Implement the route**

Copy the validation and morning-recalibration try/catch from `src/app/api/presentation/today/route.ts`. After `buildTodayPresentationViewModel`, return `NextResponse.json(projectV1TodayFromViewModel(viewModel, { trainingDayId, webOrigin }))` — not `{ viewModel }`. 500 message stays `Impossible de produire la vue Today`.

Do not add `/api/v1` to `isPublicRoute` in `src/proxy.ts`.

- [ ] **Step 4: Run — expect PASS**

```bash
yarn test src/app/api/v1/today/route.test.ts src/lib/presentation/v1/today.test.ts
```

- [ ] **Step 5: Commit**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT
git add src/app/api/v1/today/route.ts src/app/api/v1/today/route.test.ts
git commit -m "$(cat <<'EOF'
feat: add GET /api/v1/today canonical today payload

EOF
)"
```

---

### Task 5: ADR-040 — iOS product, canonical `/api/v1`

**Repo:** `SHARPIT`

**Files:**
- Create: `docs/adr/ADR-040-canonical-v1-api-ios-product.md`
- Modify: `docs/adr/README.md` if it lists ADRs
- Modify: `README.md` — one line under Modules or Architecture pointing at `/api/v1/today` and the iOS client

**Interfaces:**
- Consumes: this spec
- Produces: accepted ADR

- [ ] **Step 1: Write ADR-040**

Follow `docs/adr/ADR-template.md`. Status Accepted, date 2026-09-15, supersedes N/A.

**Decision:** Adopt `/api/v1/*` as the canonical client-agnostic HTTP contract. iOS is the product client; the Next.js UI is complementary and may keep `/api/presentation/*` until it migrates.

**Alternatives:** (1) iOS consumes `/api/presentation/today` — rejected, Tailwind/`href` leakage. (2) Device-side Twin — rejected, Core stays server. (3) WKWebView wrap of the PWA — rejected, not a native product.

**Consequences:** Two JSON shapes until web migrates; Bearer Clerk JWT from native; no CORS work for `URLSession`.

**Review criteria:** Revisit if a second native client needs a field the projector dropped, or if web fully migrates and `/api/presentation/today` can be deleted.

- [ ] **Step 2: README pointer**

Add that native clients use `GET /api/v1/today`, not presentation routes.

- [ ] **Step 3: Commit**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT
git add docs/adr/ADR-040-canonical-v1-api-ios-product.md README.md docs/adr/README.md
git commit -m "$(cat <<'EOF'
docs(adr): record iOS as product and canonical /api/v1 contract

EOF
)"
```

---

### Task 6: Gate 2 — Clerk prebuilt auth

**Repo:** `SHARPIT-APP`

**Blocked on human:** Clerk Dashboard → enable Native API; register iOS app (`app.sharpit.ios` + Apple Team ID prefix); Associated Domains `webcredentials:{FRONTEND_API_HOST}`; publishable key (same as the web app). Do not invent a second Clerk application. Do not commit a secret that is not the publishable key.

**Files:**
- Modify: `SHARPIT-APP/App/SharpitApp.swift`
- Create: `SHARPIT-APP/App/RootView.swift`, `SHARPIT-APP/Auth/AuthGate.swift`
- Modify: Xcode SPM (`https://github.com/clerk/clerk-ios`, up-to-next-major from latest 1.x), products `ClerkKit` + `ClerkKitUI`
- Add Associated Domains capability

**Interfaces:**
- Consumes: `Clerk.configure(publishableKey:)`, `Clerk.shared`
- Produces: signed-in `clerk.user != nil` gate

- [ ] **Step 1: Add the package and compile with configure only**

```swift
import SwiftUI
import ClerkKit

@main
struct SharpitApp: App {
    init() {
        Clerk.configure(publishableKey: "pk_test_REPLACE_ME")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(Clerk.shared)
        }
    }
}
```

Replace `pk_test_REPLACE_ME` with the real publishable key supplied by the developer. Follow Clerk iOS quickstart: `https://clerk.com/docs/ios/getting-started/quickstart.md`.

```bash
xcodebuild -scheme SHARPIT-APP -destination 'generic/platform=iOS Simulator' build
```

Expected: BUILD SUCCEEDED. If isolation errors mention Clerk types, do not weaken Swift 6 — keep Clerk usage in the App/views, not in actors.

- [ ] **Step 2: Prebuilt signed-out / signed-in UI**

`AuthGate.swift`:

```swift
import SwiftUI
import ClerkKit
import ClerkKitUI

struct AuthGate<SignedIn: View>: View {
    @Environment(Clerk.self) private var clerk
    @State private var authIsPresented = false
    var signedIn: () -> SignedIn

    var body: some View {
        if clerk.user != nil {
            signedIn()
        } else {
            ContentUnavailableView("SHARPIT", systemImage: "figure.run") {
                Button("Se connecter") { authIsPresented = true }
            }
            .prefetchClerkImages()
            .sheet(isPresented: $authIsPresented) {
                AuthView()
            }
        }
    }
}
```

`RootView` for this task can wrap `Text("Connecté")` in `AuthGate`. Combined `AuthView()` (not sign-in-only). If Clerk environment has Apple enabled, add Sign in with Apple capability.

- [ ] **Step 3: Compile again**

Same `xcodebuild … build`. Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT-APP
git add SHARPIT-APP SHARPIT-APP.xcodeproj
git commit -m "$(cat <<'EOF'
feat: add Clerk prebuilt auth gate

EOF
)"
```

---

### Task 7: Gate 3 — DTOs + decoding tests

**Repo:** `SHARPIT-APP`

**Files:**
- Create: `SHARPIT-APP/Networking/V1Today.swift`
- Create: `SHARPIT-APPTests/Fixtures/full.json`, `empty.json`, `sparse.json`
- Test: `SHARPIT-APPTests/V1TodayDecodingTests.swift`

**Interfaces:**
- Consumes: Task 3 JSON shapes
- Produces: `struct V1TodayResponse: Codable, Sendable, Equatable`

- [ ] **Step 1: Write failing decode tests**

Copy JSON from Task 3 expectations into the three fixture files. Test:

```swift
import Foundation
import Testing
@testable import SHARPIT_APP

@Test func decodesFullHero() throws {
    let url = try #require(Bundle.module.url(forResource: "full", withExtension: "json"))
    // If the app test bundle does not use Bundle.module, load from the tests target bundle:
    // Bundle(for: Dummy.self) — prefer adding fixtures to the test synchronized group and
    // `Data(contentsOf: URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/full.json"))`
    let data = try Data(contentsOf: fixture("full.json"))
    let decoded = try JSONDecoder().decode(V1TodayResponse.self, from: data)
    #expect(decoded.apiVersion == 1)
    #expect(decoded.empty == nil)
    #expect(decoded.verdict.posture == .steady)
    #expect(decoded.sessions.first?.kind == .planned)
    #expect(decoded.signals.count == 4)
}

@Test func decodesEmptyNoContent() throws {
    let decoded = try JSONDecoder().decode(V1TodayResponse.self, from: try Data(contentsOf: fixture("empty.json")))
    #expect(decoded.empty?.code == .noContent)
    #expect(decoded.empty?.webURL.hasPrefix("https://") == true)
}

@Test func decodesSparseWeatherAndSessions() throws {
    let decoded = try JSONDecoder().decode(V1TodayResponse.self, from: try Data(contentsOf: fixture("sparse.json")))
    #expect(decoded.weather == nil)
    #expect(decoded.sessions.isEmpty)
}

private func fixture(_ name: String) -> URL {
    URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
}
```

Use `@testable import` matching the app module name (`SHARPIT_APP` if the product is `SHARPIT-APP`; confirm with `PRODUCT_MODULE_NAME`). If hyphenated, set `PRODUCT_MODULE_NAME = Sharpit` in the app target and import `Sharpit`.

- [ ] **Step 2: Run tests — expect FAIL** (type missing)

```bash
xcodebuild -scheme SHARPIT-APP -destination 'generic/platform=iOS Simulator' test
```

- [ ] **Step 3: Implement DTOs**

`SHARPIT-APP/Networking/V1Today.swift`:

```swift
import Foundation

struct V1TodayResponse: Codable, Sendable, Equatable {
    var apiVersion: Int
    var trainingDayId: String
    var empty: V1TodayEmpty?
    var verdict: V1TodayVerdict
    var weather: V1TodayWeather?
    var sessions: [V1TodaySession]
    var signals: [V1TodaySignal]
}

struct V1TodayEmpty: Codable, Sendable, Equatable {
    var title: String
    var message: String?
    var code: V1TodayEmptyCode
    var webURL: String
}

enum V1TodayEmptyCode: String, Codable, Sendable {
    case noContent = "NO_CONTENT"
}

struct V1TodayVerdict: Codable, Sendable, Equatable {
    var eyebrow: String
    var headline: String
    var subline: String
    var posture: V1TodayPosture
    var confidencePct: Int?
    var limitingCause: String?
}

enum V1TodayPosture: String, Codable, Sendable {
    case protect, steady, push, uncertain
}

struct V1TodayWeather: Codable, Sendable, Equatable {
    var city: String
    var tempC: Double
    var condition: String
}

struct V1TodaySession: Codable, Sendable, Equatable {
    var id: String
    var kind: V1TodaySessionKind
    var title: String
    var subtitle: String?
    var metrics: [V1TodayMetric]
}

enum V1TodaySessionKind: String, Codable, Sendable {
    case planned, done
}

struct V1TodayMetric: Codable, Sendable, Equatable {
    var label: String
    var value: String
    var unit: String
}

struct V1TodaySignal: Codable, Sendable, Equatable {
    var key: V1TodaySignalKey
    var score: String
    var caption: String?
}

enum V1TodaySignalKey: String, Codable, Sendable {
    case sleep, recovery, effort, adaptation
}
```

No Clerk, no SwiftUI in this file.

- [ ] **Step 4: Run tests — expect PASS**

Same `xcodebuild test`.

- [ ] **Step 5: Commit**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT-APP
git add SHARPIT-APP/Networking/V1Today.swift SHARPIT-APPTests
git commit -m "$(cat <<'EOF'
feat: decode canonical v1 today payloads

EOF
)"
```

---

### Task 8: Gate 4 — `TodayServing`, `TodayModel`, fixture UI, tab shell

**Repo:** `SHARPIT-APP`

**Files:**
- Create: `SHARPIT-APP/Networking/APIConfiguration.swift`
- Create: `SHARPIT-APP/Networking/SharpitClient.swift`
- Create: `SHARPIT-APP/Features/Today/TodayModel.swift`
- Create: `SHARPIT-APP/Features/Today/TodayView.swift`
- Create: `SHARPIT-APP/Features/Shell/PlaceholderTab.swift`
- Modify: `SHARPIT-APP/App/RootView.swift`
- Create: `SHARPIT-APP/Info.plist` (`NSAllowsLocalNetworking = true`)
- Test: `SHARPIT-APPTests/TodayModelTests.swift`

**Interfaces:**
- Consumes: `V1TodayResponse`
- Produces:
  - `protocol TodayServing: Sendable { func today(trainingDayId: String, token: String) async throws -> V1TodayResponse }`
  - `actor SharpitClient: TodayServing`
  - `enum TodayScreenState: Equatable { case loading, loaded(V1TodayResponse), empty(V1TodayEmpty), failed(String) }`
  - `enum TodayModel` with `static func state(from response: V1TodayResponse) -> TodayScreenState` — if `response.empty != nil` → `.empty`, else `.loaded`

- [ ] **Step 1: Failing `TodayModel` tests**

```swift
import Testing
@testable import Sharpit

@Test func emptyPayloadWinsOverVerdict() throws {
    let data = try Data(contentsOf: fixture("empty.json"))
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: data)
    let state = TodayModel.state(from: response)
    guard case .empty(let empty) = state else {
        Issue.record("expected empty")
        return
    }
    #expect(empty.code == .noContent)
}

@Test func fullPayloadIsLoaded() throws {
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: try Data(contentsOf: fixture("full.json")))
    let state = TodayModel.state(from: response)
    guard case .loaded(let loaded) = state else {
        Issue.record("expected loaded")
        return
    }
    #expect(loaded.weather != nil)
}
```

- [ ] **Step 2: Run — expect FAIL**

- [ ] **Step 3: Implement model, actor, views**

`APIConfiguration.swift`:

```swift
import Foundation

enum APIConfiguration {
    static var baseURL: URL {
        #if DEBUG
        URL(string: "http://127.0.0.1:3000")!
        #else
        URL(string: "https://REPLACE_PRODUCTION_ORIGIN")!
        #endif
    }
}
```

Ask the developer for the production origin before Release use. Debug stays loopback.

`SharpitClient.swift`:

```swift
import Foundation

protocol TodayServing: Sendable {
    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse
}

enum SharpitAPIError: Error, Equatable {
    case unauthorized
    case badRequest
    case server
    case transport
}

actor SharpitClient: TodayServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func today(trainingDayId: String, token: String) async throws -> V1TodayResponse {
        var components = URLComponents(url: baseURL.appending(path: "/api/v1/today"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "trainingDayId", value: trainingDayId)]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            break
        case 400:
            throw SharpitAPIError.badRequest
        case 401:
            throw SharpitAPIError.unauthorized
        default:
            throw SharpitAPIError.server
        }
        do {
            return try JSONDecoder().decode(V1TodayResponse.self, from: data)
        } catch {
            throw SharpitAPIError.server
        }
    }
}
```

`TodayView`: switch on `TodayScreenState`. Loading = `.redacted` placeholders. Empty = title, message, button `Link`/`openURL` to `webURL`. Loaded = verdict, then sessions, then signals, weather if non-nil. Pull-to-refresh later in Task 9.

`PlaceholderTab(title:)` shows `ContentUnavailableView(title, systemImage: "clock") { Text("Bientôt") }`.

`RootView`: `AuthGate` wrapping `TabView` with five tabs (Résumé = `TodayView` with a `PreviewTodayClient` fixture in DEBUG previews; live client in Task 9). For Gate 4 compile, inject a struct `FixtureTodayClient: TodayServing` that returns the decoded `full.json` payload without URLSession.

`TrainingDayId.today(in: Calendar = .current) -> String` using `yyyy-MM-dd` in the device calendar.

- [ ] **Step 4: Compile and test**

```bash
xcodebuild -scheme SHARPIT-APP -destination 'generic/platform=iOS Simulator' test
```

Expected: TEST SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT-APP
git add SHARPIT-APP SHARPIT-APPTests
git commit -m "$(cat <<'EOF'
feat: render Résumé from v1 fixtures behind TodayServing

EOF
)"
```

---

### Task 9: Gate 5 — live fetch + pull-to-refresh

**Repo:** `SHARPIT-APP`

**Files:**
- Modify: `SHARPIT-APP/Features/Today/TodayView.swift` (or a `TodayViewModel` `@Observable` class)
- Modify: `SHARPIT-APP/App/RootView.swift` to construct `SharpitClient()` when signed in

**Interfaces:**
- Consumes: `clerk.auth.getToken()`, `SharpitClient.today(trainingDayId:token:)`
- Produces: live Résumé against local `yarn dev`

- [ ] **Step 1: Wire the main-actor fetch**

```swift
let token = try await clerk.auth.getToken()
guard let token else { throw SharpitAPIError.unauthorized }
let day = TrainingDayId.today()
let payload = try await client.today(trainingDayId: day, token: token)
screenState = TodayModel.state(from: payload)
```

On `SharpitAPIError.unauthorized`, present signed-out UI (Clerk user should already be nil; if not, still show the auth sheet). On `.transport` / `.server` / `.badRequest`, `screenState = .failed` with a retry button. `.refreshable` calls the same method.

No unit test that hits the network. Manual: `yarn dev` in SHARPIT, simulator, sign in, pull to refresh.

- [ ] **Step 2: Compile**

```bash
xcodebuild -scheme SHARPIT-APP -destination 'generic/platform=iOS Simulator' test
```

- [ ] **Step 3: Commit**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT-APP
git add SHARPIT-APP
git commit -m "$(cat <<'EOF'
feat: load Résumé from GET /api/v1/today

EOF
)"
```

---

### Task 10: iOS README

**Repo:** `SHARPIT-APP`

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write README**

English. Include: iPhone / Xcode 27 / Swift 6.4; `xcodebuild` command; Clerk Native API + Associated Domains; Debug API `http://127.0.0.1:3000`; complementary web is the SHARPIT repo; spec and this plan under `docs/superpowers/`.

- [ ] **Step 2: Commit**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT-APP
git add README.md
git commit -m "$(cat <<'EOF'
docs: add iOS app setup and API contract pointer

EOF
)"
```

---

## Spec coverage

| Spec section | Task |
| --- | --- |
| iPhone-only / Playgrounds / Swift 6 | 1 |
| Test target | 2 |
| `/api/v1/today` projector + route | 3–4 |
| ADR + web README | 5 |
| Clerk prebuilt + Native API | 6 |
| Codable fixtures | 7 |
| Tab shell, empty/loading, actor, ATS | 8 |
| Live GET + refresh | 9 |
| iOS README | 10 |
| Out of scope (HealthKit, writes, presentation routes) | not scheduled |

## Self-review notes

- Module import name (`Sharpit` vs `SHARPIT_APP`) is confirmed in Task 7 against `PRODUCT_MODULE_NAME`.
- Production HTTPS origin is a developer-supplied value in `APIConfiguration`, not guessed.

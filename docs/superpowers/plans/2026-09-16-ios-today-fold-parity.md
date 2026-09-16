# Today Fold Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich `GET /api/v1/today` additively and rebuild native Today as an ink-plate fold (verdict → session → overnight gauges) matching the live web Résumé.

**Architecture:** SHARPIT projection filters overnight signals and adds verdict/session fields without Tailwind/`href`. iOS maps JSON to a pure `TodayFold` value, loads via `@MainActor TodayStore`, and composes `InkVerdictPlate` + `SessionInstrumentCard`/`RestDayPlate` + `OvernightGaugePair` under `TodayArrivalDirector` (SharpitMotion).

**Tech Stack:** Next.js/Vitest (SHARPIT) · Swift 6 / SwiftUI / Swift Testing (SHARPIT-APP) · existing Clerk + `SharpitClient` actor · `SharpitMotion` / `SharpitHaptics`

## Global Constraints

- Spec: `docs/superpowers/specs/2026-09-16-ios-today-fold-parity-design.md` (SHARPIT-APP)
- `apiVersion` stays `1` (additive JSON only)
- No Tailwind class names, no `href` in v1 JSON
- Résumé signals = `sleep` + `recovery` only
- All iOS animation via `SharpitMotion`; respect reduce motion
- Two git repos: commit API work in `/Users/H6245/Documents/DEV/PERSO/SHARPIT`, iOS work in `/Users/H6245/Documents/DEV/PERSO/SHARPIT-APP` — never cross-add
- Artifacts in English; user-facing copy stays server French
- Conventional Commits; no Cursor/AI co-author trailers
- Out of scope: Plan vivant, nutrition, Coach chrome, SwiftData snapshot (tranche 2)

## File map

### SHARPIT

| File | Role |
| --- | --- |
| `src/lib/presentation/v1/today.ts` | Extend `V1TodaySource` / `V1TodayResponse` + `projectV1Today` |
| `src/lib/presentation/v1/today.test.ts` | Vitest for signals filter + new fields |
| `docs/adr/` (optional short note) | Only if team wants ADR for additive fields |

### SHARPIT-APP

| File | Role |
| --- | --- |
| `SHARPIT-APP/Networking/V1Today.swift` | Decode new fields |
| `SHARPIT-APPTests/Fixtures/full.json` (+ sparse) | Fixture parity |
| `SHARPIT-APPTests/V1TodayDecodingTests.swift` | Expect 2 signals + new keys |
| `SHARPIT-APP/Features/Today/TodayFold.swift` | Presentation model + mapper + confidence bars |
| `SHARPIT-APPTests/TodayFoldTests.swift` | Mapper / bars / packTier tones |
| `SHARPIT-APP/DesignSystem/InkVerdictPlate.swift` | Ink plate UI |
| `SHARPIT-APP/DesignSystem/OvernightGaugePair.swift` | Twin gauges |
| `SHARPIT-APP/DesignSystem/SessionPlate.swift` | Evolve or wrap as session instrument card |
| `SHARPIT-APP/DesignSystem/SharpitLoadingInstrument.swift` | Placeholder = same 3 blocks |
| `SHARPIT-APP/Features/Today/TodayArrivalDirector.swift` | Phase choreography |
| `SHARPIT-APP/Features/Today/TodayStore.swift` | Replace/slim `TodayController` |
| `SHARPIT-APP/Features/Today/TodayView.swift` | Wire fold UI |
| `SHARPIT-APP/Networking/FixtureTodayClient.swift` | Return enriched fixture |

---

### Task 1: API — filter overnight signals + verdict fields

**Repo:** `SHARPIT`

**Files:**
- Modify: `src/lib/presentation/v1/today.ts`
- Modify: `src/lib/presentation/v1/today.test.ts`
- Consume: `activityTypeLabels` from `@/lib/format` for session sport
- Consume: hero `postureLabel`, `focusPriority`, `twinTrustStrip.confidenceLabel`, `reliability`

**Interfaces:**
- Produces: additive `V1TodayResponse` shape used by iOS Task 2

- [ ] **Step 1: Write failing Vitest for overnight-only signals and new verdict fields**

In `today.test.ts`, extend `source()` hero with:

```ts
postureLabel: 'FEU VERT',
focusPriority: 'Entraîne-toi — légèrement',
twinTrustStrip: {
  confidencePctRounded: 72,
  limitingCauseText: 'Sommeil',
  confidenceLabel: 'ESTIMATION PARTIELLE',
},
reliability: {
  packTier: 'PARTIAL',
  visibleGaps: ['Baseline HRV partielle (moins de 14 j)'],
},
```

Add assertions:

```ts
expect(json.signals.map((s) => s.key)).toEqual(['sleep', 'recovery']);
expect(json.verdict.statusLabel).toBe('FEU VERT');
expect(json.verdict.actionLine).toBe('Entraîne-toi — légèrement');
expect(json.verdict.confidenceLabel).toBe('ESTIMATION PARTIELLE');
expect(json.verdict.packTier).toBe('PARTIAL');
expect(json.verdict.estimationGaps).toEqual(['Baseline HRV partielle (moins de 14 j)']);
expect(JSON.stringify(json)).not.toMatch(/href|bgClass|rounded-/);
```

Update `V1TodaySource` in the test helper to include the new optional hero fields.

- [ ] **Step 2: Run test — expect FAIL**

Run: `cd /Users/H6245/Documents/DEV/PERSO/SHARPIT && yarn vitest run src/lib/presentation/v1/today.test.ts`  
Expected: FAIL (missing properties / still 4 signals)

- [ ] **Step 3: Implement projection**

Update `V1TodaySource` + `V1TodayResponse` and `projectV1Today`:

```ts
// verdict extras
statusLabel: source.hero.postureLabel?.trim() || source.hero.eyebrow,
actionLine:
  source.hero.focusPriority?.trim() ||
  source.hero.actionLine?.trim() ||
  source.hero.subline,
confidenceLabel: source.hero.twinTrustStrip.confidenceLabel ?? null,
packTier: source.hero.reliability?.packTier ?? null,
estimationGaps: [...(source.hero.reliability?.visibleGaps ?? [])],

// signals
signals: source.hero.signalPreviews
  .filter((s) => s.key === 'sleep' || s.key === 'recovery')
  .map((s) => ({ key: s.key, score: s.scoreDisplay, caption: s.subtitle })),

// sessions — sport from activityType; priority = first line
sessions: source.actionRow.daySummaryLines.map((line, index) => ({
  id: line.id,
  kind: line.kind,
  title: line.primary,
  subtitle: line.secondary ?? null,
  metrics: line.metrics ?? [],
  sport: activityTypeLabels[line.activityType] ?? null,
  priority: index === 0 ? true : false,
})),
```

Extend `V1TodaySource` so `projectV1TodayFromViewModel(vm)` still type-checks: pull `postureLabel`, `focusPriority`, `actionLine`, `reliability`, and daySummary `activityType` from the real `TodayViewModel` (cast/narrow in `projectV1TodayFromViewModel` if `V1TodaySource` stays a subset).

Prefer implementing `projectV1TodayFromViewModel` by mapping VM → source explicitly rather than `projectV1Today(vm as any)`.

- [ ] **Step 4: Run Vitest — expect PASS**

Run: `yarn vitest run src/lib/presentation/v1/today.test.ts`  
Expected: PASS

- [ ] **Step 5: Commit in SHARPIT**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT
git add src/lib/presentation/v1/today.ts src/lib/presentation/v1/today.test.ts
git commit -m "$(cat <<'EOF'
feat: enrich v1 today projection for native fold parity

Filter résumé signals to overnight sleep/recovery and add verdict trust fields plus session sport/priority without leaking web hrefs.
EOF
)"
```

---

### Task 2: iOS — decode enriched payload + fixtures

**Repo:** `SHARPIT-APP`

**Files:**
- Modify: `SHARPIT-APP/Networking/V1Today.swift`
- Modify: `SHARPIT-APPTests/Fixtures/full.json`
- Modify: `SHARPIT-APPTests/V1TodayDecodingTests.swift`
- Modify: `SHARPIT-APP/Networking/FixtureTodayClient.swift`

**Interfaces:**
- Consumes: Task 1 JSON shape
- Produces: updated `V1TodayVerdict` / `V1TodaySession` for mapper

- [ ] **Step 1: Write failing decode expectations**

Update `full.json` verdict:

```json
"statusLabel": "FEU VERT",
"actionLine": "Entraîne-toi — légèrement",
"confidenceLabel": "ESTIMATION PARTIELLE",
"packTier": "PARTIAL",
"estimationGaps": ["Baseline HRV partielle (moins de 14 j)"]
```

Sessions entry add `"sport": "Course", "priority": true`.  
Signals array: only sleep + recovery.

In `decodesFullHero`:

```swift
#expect(decoded.signals.count == 2)
#expect(decoded.verdict.statusLabel == "FEU VERT")
#expect(decoded.verdict.packTier == .partial)
#expect(decoded.sessions.first?.sport == "Course")
#expect(decoded.sessions.first?.priority == true)
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `xcodebuild -scheme SHARPIT-APP -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:SHARPIT-APPTests/decodesFullHero test`  
Expected: FAIL (unknown keys ignored / count still 4 / missing properties)

- [ ] **Step 3: Extend Swift models**

```swift
enum V1TodayPackTier: String, Codable, Sendable {
    case full = "FULL"
    case partial = "PARTIAL"
    case low = "LOW"
    case insufficient = "INSUFFICIENT"
}

// on V1TodayVerdict — all optional for backward compatibility
var statusLabel: String?
var actionLine: String?
var confidenceLabel: String?
var packTier: V1TodayPackTier?
var estimationGaps: [String]?

// on V1TodaySession
var sport: String?
var priority: Bool?
```

Update `FixtureTodayClient` to match enriched fixture.

- [ ] **Step 4: Run decode tests — expect PASS**

Run: same `xcodebuild … -only-testing:SHARPIT-APPTests` (or full test target)  
Expected: PASS for decoding tests

- [ ] **Step 5: Commit**

```bash
cd /Users/H6245/Documents/DEV/PERSO/SHARPIT-APP
git add SHARPIT-APP/Networking/V1Today.swift SHARPIT-APP/Networking/FixtureTodayClient.swift \
  SHARPIT-APPTests/Fixtures/full.json SHARPIT-APPTests/V1TodayDecodingTests.swift
git commit -m "$(cat <<'EOF'
feat: decode enriched v1 today fields for fold parity

Accept additive verdict trust fields and overnight-only signal fixtures so native mapping can match the web résumé fold.
EOF
)"
```

---

### Task 3: iOS — `TodayFold` mapper + confidence bars (TDD)

**Repo:** `SHARPIT-APP`

**Files:**
- Create: `SHARPIT-APP/Features/Today/TodayFold.swift`
- Create: `SHARPIT-APPTests/TodayFoldTests.swift`

**Interfaces:**
- Consumes: `V1TodayResponse`
- Produces: `TodayFold`, `TodayFoldMapper.map(_:)`, `ConfidenceBars.filled(fromPct:)`

- [ ] **Step 1: Write failing mapper tests**

```swift
import Testing
@testable import Sharpit

@Test func foldKeepsOnlyOvernightGauges() throws {
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    let fold = TodayFoldMapper.map(response)
    #expect(fold.gauges.map(\.key) == [.sleep, .recovery])
}

@Test func confidenceBarsMatchWebThresholds() {
    #expect(ConfidenceBars.filled(fromPct: nil) == 0)
    #expect(ConfidenceBars.filled(fromPct: 10) == 1)
    #expect(ConfidenceBars.filled(fromPct: 34) == 2)
    #expect(ConfidenceBars.filled(fromPct: 67) == 3)
}

@Test func packTierDotTone() {
    #expect(PackTierTone.dot(for: .full) == .highlight)
    #expect(PackTierTone.dot(for: .partial) == .caution)
    #expect(PackTierTone.dot(for: .insufficient) == .muted)
}
```

- [ ] **Step 2: Run — expect FAIL**

Run: `xcodebuild … -only-testing:SHARPIT-APPTests/foldKeepsOnlyOvernightGauges test`  
Expected: FAIL (types missing)

- [ ] **Step 3: Implement `TodayFold.swift`**

```swift
struct TodayFold: Sendable, Equatable {
    var trainingDayId: String
    var plate: InkPlateModel
    var sessions: [SessionCardModel]
    var gauges: [OvernightGaugeModel]
    var weather: V1TodayWeather?
}

struct InkPlateModel: Sendable, Equatable {
    var statusLabel: String
    var headline: String
    var actionLine: String?
    var limitingCause: String?
    var confidencePct: Int?
    var confidenceLabel: String?
    var packTier: V1TodayPackTier?
    var estimationGaps: [String]
    var posture: V1TodayPosture
}

enum ConfidenceBars {
    static func filled(fromPct pct: Int?) -> Int {
        guard let pct else { return 0 }
        if pct >= 67 { return 3 }
        if pct >= 34 { return 2 }
        if pct > 0 { return 1 }
        return 0
    }
}

enum PackTierTone {
    case highlight, caution, muted
    static func dot(for tier: V1TodayPackTier?) -> PackTierTone { /* FULL/nil highlight; PARTIAL/LOW caution; INSUFFICIENT muted */ }
}

enum TodayFoldMapper {
    static func map(_ response: V1TodayResponse) -> TodayFold { /* … */ }
}
```

Mapper rules: fallbacks `statusLabel ← eyebrow`, `actionLine ← subline`, gaps default `[]`, gauges only sleep/recovery even if API regresses.

- [ ] **Step 4: Run TodayFold tests — PASS**

- [ ] **Step 5: Commit**

```bash
git add SHARPIT-APP/Features/Today/TodayFold.swift SHARPIT-APPTests/TodayFoldTests.swift
git commit -m "$(cat <<'EOF'
feat: add TodayFold presentation mapper for résumé parity

Isolate API DTOs from UI with overnight-only gauges and web-matched confidence bar thresholds.
EOF
)"
```

---

### Task 4: Design system — Ink plate + overnight gauges + session card

**Repo:** `SHARPIT-APP`

**Files:**
- Create: `SHARPIT-APP/DesignSystem/InkVerdictPlate.swift`
- Create: `SHARPIT-APP/DesignSystem/OvernightGaugePair.swift`
- Modify: `SHARPIT-APP/DesignSystem/SessionPlate.swift` (accept `SessionCardModel` or keep `V1TodaySession` + sport/priority)
- Modify: `SHARPIT-APP/DesignSystem/SharpitTheme.swift` (ink colors + packTier colors)
- Modify: `SHARPIT-APP/DesignSystem/SharpitLoadingInstrument.swift`

**Interfaces:**
- Consumes: `InkPlateModel`, `OvernightGaugeModel`, session models
- Produces: pure SwiftUI views + `#Preview`

- [ ] **Step 1: Add ink tokens**

```swift
enum SharpitInk {
    static let surface = Color(red: 0.11, green: 0.12, blue: 0.09) // approx web ink
    static let foreground = Color.white.opacity(0.92)
    static let muted = Color.white.opacity(0.55)
    static let highlight = Color(red: 0.83, green: 1.0, blue: 0.2) // lime pulse approx
    static let caution = Color.orange
}
```

- [ ] **Step 2: Build `InkVerdictPlate`**

Pure view: status dot + label, headline, actionLine, limiter, 3 confidence bars + label, gaps. Support `placeholder: Bool` for redacted loading. No networking.

- [ ] **Step 3: Build `OvernightGaugePair`**

`HStack` of two gauge cells; arc fill animated via `SharpitMotion` + `AnimatedNumber`; empty score → stable dash.

- [ ] **Step 4: Session card tags**

Show `sport` chip and `PRIORITAIRE` when `priority == true`; keep metrics row; rest day still `RestDayPlate`.

- [ ] **Step 5: Loading instrument = same three blocks in fold order**

verdict ink placeholder → session placeholder → gauge pair placeholder (redacted).

- [ ] **Step 6: Previews compile**

Run: `xcodebuild -scheme SHARPIT-APP -destination 'platform=iOS Simulator,name=iPhone 17' build`  
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add ink verdict plate and overnight gauge pair

Introduce native instrument surfaces for the Today fold so résumé hierarchy matches the web decision plate.
EOF
)"
```

---

### Task 5: `TodayStore` + arrival director + wire TodayView

**Repo:** `SHARPIT-APP`

**Files:**
- Create: `SHARPIT-APP/Features/Today/TodayStore.swift`
- Create: `SHARPIT-APP/Features/Today/TodayArrivalDirector.swift`
- Modify: `SHARPIT-APP/Features/Today/TodayView.swift`
- Modify: `SHARPIT-APP/App/RootView.swift` if initializer changes
- Remove/slim: logic currently in `TodayController` inside `TodayView.swift`

**Interfaces:**
- Consumes: `TodayServing`, `TodayFoldMapper`, win store, motion
- Produces: loaded fold UI in causal order

- [ ] **Step 1: Implement `@MainActor @Observable TodayStore`**

```swift
@MainActor
@Observable
final class TodayStore {
    enum Phase: Equatable {
        case loading
        case loaded(TodayFold)
        case empty(V1TodayEmpty)
        case failed(String)
        case unauthorized
    }
    var phase: Phase = .loading
    var pulseScores = false
    // load(resetToLoading:), refresh(), handleArrivalWins(fold:)
}
```

Rules: ignore `CancellationError`; refresh does not force skeleton; map via `TodayFoldMapper` after `TodayModel.state`.

- [ ] **Step 2: `TodayArrivalDirector`**

Phases: `plate` → `session` → `gauges` → `idle` with `SharpitMotion.staggerDelay`; reduce motion snaps all visible.

- [ ] **Step 3: Rebuild `TodayView` body**

Order: `InkVerdictPlate` → sessions/Rest → `OvernightGaugePair`.  
`.task { await store.load(resetToLoading: true) }`  
`.refreshable { await store.refresh() }`

- [ ] **Step 4: Run unit tests + build**

Run: full `SHARPIT-APPTests` + build  
Expected: TEST SUCCEEDED / BUILD SUCCEEDED

- [ ] **Step 5: Manual QA checklist (simulator)**

- Same athlete-day as web: ink plate status + headline + frein + estimation  
- Session card shows planned workout (not false Rest) when API has sessions  
- Exactly two gauges  
- Reduce Motion ON: no spring/stagger  
- Pull-to-refresh: light haptic, no full skeleton flash  

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: wire Today fold with store and arrival choreography

Replace the metric-strip résumé with ink plate, session evidence, and overnight gauges driven by SharpitMotion.
EOF
)"
```

---

### Task 6: Docs sync + push coordination

**Files:**
- Modify: `SHARPIT-APP/docs/superpowers/specs/2026-09-16-ios-today-fold-parity-design.md` status → Implemented (when done)
- Optionally note in SHARPIT README API section if one exists for `/api/v1/today`

- [ ] **Step 1: Mark spec status Implemented**
- [ ] **Step 2: Commit docs**
- [ ] **Step 3: Push each repo only when user asks** (`main` protected — explicit push)

---

## Spec coverage check

| Spec § | Task |
| --- | --- |
| 5.1 overnight signals | 1 |
| 5.2 verdict fields | 1–2 |
| 5.3 session sport/priority | 1–2, 4 |
| 6 Fold mapper / store | 3, 5 |
| 7 components | 4 |
| 8 motion director | 5 |
| 9 SwiftData | deferred (explicit) |
| 10 testing | 1–5 |
| 11 order | tasks 1→5 |

## Placeholder scan

No TBD steps; commands and types named above.

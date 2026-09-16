# SHARPIT iOS — Today fold parity (API + native)

**Date:** 2026-09-16  
**Status:** Implemented  
**Repos:** `SHARPIT-APP` (iOS) · `SHARPIT` (canonical API)  
**Related:** [2026-09-15-ios-native-v1-design.md](./2026-09-15-ios-native-v1-design.md), [2026-09-16-ios-emotional-ux-design.md](./2026-09-16-ios-emotional-ux-design.md), SHARPIT `docs/design/DESIGN_LANGUAGE.md`

## 1. Problem

Live web Résumé is an **instrument column** (ink verdict plate → rich session → overnight gauges). Native Today is a **system-chrome metric strip** (flat hero + four equal tiles + rest plate). Same Twin copy, different composition — athletes feel “far” from the product.

## 2. Goal

Close the **first-viewport gap** while staying **full native SwiftUI** (no WebView). Enrich `GET /api/v1/today` additively so iOS can paint the fold without inventing fields.

**Success:** side-by-side with live `/` for the same athlete-day, iOS reads as the same argument: decision → session evidence → overnight proof.

## 3. Non-goals (this tranche)

- Plan vivant, nutrition, régularité, journal bridge  
- Coach / Actif / Journal action chrome  
- Drill-down routes (`/today/sleep`, …)  
- Dark “Forest Depths” skin as a separate product track (system + ink plate is enough)  
- SwiftData offline cache (tranche 2 — see §8)

## 4. Approach

**Additive `apiVersion: 1` enrichment** + iOS presentation layer (`TodayFold`) + arrival choreography. Rejected: `apiVersion: 2` (unnecessary fork); iOS-only hardcoding (session/rest mismatch stays wrong).

## 5. API contract (`SHARPIT`)

File: `src/lib/presentation/v1/today.ts` (+ Vitest).

### 5.1 Signals

Project **only** `sleep` and `recovery` (same rule as `pickTodayResumeSignalPreviews`). Adaptation / effort stay on Plan (web), not Résumé.

### 5.2 Verdict (additive fields)

Keep existing: `eyebrow`, `headline`, `subline`, `posture`, `confidencePct`, `limitingCause`.

Add:

| Field | Source (TodayViewModel) | Example |
| --- | --- | --- |
| `statusLabel` | `hero.postureLabel` (fallback eyebrow) | `"FEU VERT"` |
| `actionLine` | `focusPriority` / action line (fallback `subline`) | `"Entraîne-toi — légèrement"` |
| `confidenceLabel` | `twinTrustStrip.confidenceLabel` | `"ESTIMATION PARTIELLE"` |
| `packTier` | `hero.reliability?.packTier` | `FULL \| PARTIAL \| LOW \| INSUFFICIENT` \| `null` |
| `estimationGaps` | `reliability.visibleGaps` | `["Baseline HRV partielle (moins de 14 j)"]` |

No `href`, no Tailwind, no CSS class names in JSON.

### 5.3 Sessions (additive, nullable)

Keep: `id`, `kind`, `title`, `subtitle`, `metrics`.

Add only when already present on day-summary lines (no invention):

| Field | Notes |
| --- | --- |
| `sport` | e.g. `"Course"` — `null` if absent |
| `priority` | e.g. `true` when PRIORITAIRE — `null`/`false` if absent |

If the VM does not yet expose these on `daySummaryLines`, ship `null` and leave tags off iOS until Core projection is extended in the same PR or a tiny follow-up — **do not fabricate**.

### 5.4 Compatibility

- `apiVersion` remains `1`.  
- Older iOS builds ignoring new keys keep working; they will see two signals instead of four (intentional).

## 6. iOS architecture

```text
SharpitClient (actor) → V1TodayResponse
        ↓
TodayFoldMapper (pure) → TodayFold
        ↓
TodayStore (@MainActor, @Observable)
        ↓
TodayView
  InkVerdictPlate · SessionInstrumentCard · OvernightGaugePair
  TodayArrivalDirector (phases + SharpitMotion + SharpitHaptics)
```

### 6.1 Presentation model

`TodayFold` is a `Sendable` value type: verdict plate inputs, sessions, overnight gauges (`sleep`/`recovery` only), weather. Views **never** bind to raw `V1TodayResponse` fields for layout decisions.

Mapper unit-tested: four API signals → two gauges; empty sessions → rest plate; packTier → dot tone.

### 6.2 Store (concurrency)

- `@MainActor @Observable final class TodayStore`  
- Load via `.task` / `.refreshable`; treat `CancellationError` as no-op  
- Do not flip to skeleton on pull-to-refresh if already loaded  
- Wins / pulse stay in store or thin helpers — not inside leaf views  
- Prefer structured work; avoid fire-and-forget `Task {}` loops for UI flash without cancellation awareness

### 6.3 View purity

- Leaf plates are pure: inputs in, no networking, no UserDefaults  
- Composition in `TodayView` / small section wrappers  
- `#Preview` with fixture `TodayFold` for plate / gauges / session / rest

## 7. Components & visual tokens

### 7.1 `InkVerdictPlate`

Ink surface (dark olive / near-black), generous padding, large radius — mirrors web `surface-ink`.

Contents (top → bottom):

1. Status row: **dot** (decision tone from `statusLabel`, e.g. FEU VERT → lime) + `statusLabel` uppercase mono/data  
2. `headline` — verdict weight (system rounded semi-bold until custom fonts land)  
3. `actionLine` — secondary  
4. Limiter — `LIMITÉ PAR · {cause}` uppercase data (non-interactive this tranche)  
5. Confidence — **3 bars** from `confidencePct` (same thresholds as web `confidenceBarsFromPct`: 0 / 1–33 / 34–66 / 67–100) + `confidenceLabel`  
6. Gaps — bullet list from `estimationGaps` (muted)

**Status dot (native):** follows the feu label (`VERT` → lime, `ORANGE`/`JAUNE` → amber, `ROUGE` → muted) so “FEU VERT” is never paired with a caution dot.

**Pack tier bar tones (native, trust chrome):**

| packTier | Bars |
| --- | --- |
| `FULL` / nil | Lime / highlight |
| `PARTIAL` / `LOW` | Caution amber |
| `INSUFFICIENT` | Muted gray on ink |

### 7.2 `SessionInstrumentCard`

- Tags: sport + optional Prioritaire  
- Title  
- Metrics row (label uppercase / value tabular)  
- Empty → existing `RestDayPlate` (Twin-legitimized rest)

### 7.3 `OvernightGaugePair`

- Exactly two cells: sleep, recovery  
- Semicircle tick gauge (or faithful thin arc) 0–100 when score parsable  
- Score + caption; count-up via `AnimatedNumber`  
- No adaptation/effort on Résumé

### 7.4 Fold order

1. Header date (nav title) + weather chip (existing)  
2. `InkVerdictPlate`  
3. Sessions / Rest  
4. `OvernightGaugePair`

## 8. Motion (instrument-grade)

Director: `TodayArrivalDirector` driven by `TodayArrivalPhase`.

| Phase | Motion | Haptic |
| --- | --- | --- |
| canvas | posture wash fade | — |
| plate | opacity + Y 12→0 via `SharpitMotion.reveal` | `.soft` once/day (`SharpitWinStore`) |
| session | settle after plate | — |
| gauges | stagger ~48 ms + arc/number fill | — |
| idle | — | refresh `.light`; session done `.success` (existing anti-spam) |

Rules (unchanged emotional contract):

- Durations 180–420 ms; snappy spring or ease-out  
- All animation through `SharpitMotion`  
- Reduce Motion → final values, no stagger/spring  
- No confetti, permanent bounce, or idle pulse

Loading: **structure-matched** placeholders of the same three blocks (ink / session / gauges), redacted — causal order identical to loaded fold.

## 9. SwiftData (tranche 2)

Cold launch paints the last successful day snapshot, then refreshes from the network.

```swift
@Model
final class TodayDaySnapshot {
  #Unique<TodayDaySnapshot>([\.trainingDayId])
  var trainingDayId: String
  var fetchedAt: Date
  var payloadJSON: Data
}
```

- Explicit `save()` after successful fetch (`TodaySnapshotRepository`)
- `#Unique` once; no `description` property
- `ModelContext` stays on MainActor; network returns DTO only
- Cold launch: show snapshot → refresh → replace; transport failure keeps stale snapshot
- Bootstrap: `SharpitPersistence.makeContainer()` on `SharpitApp`

## 10. Testing

| Layer | Tests |
| --- | --- |
| API | Vitest: sleep+recovery only; new verdict fields; no href/Tailwind in JSON |
| Mapper | Swift Testing: fold mapping, bars from pct, packTier tones |
| Motion | Existing reduce-motion / stagger contracts |
| Store | Optional: cancel load does not publish failed |

Manual QA: same athlete-day web vs iOS fold; Reduce Motion ON/OFF.

## 11. Implementation order

1. **SHARPIT** — projection + Vitest + ADR note if fields are non-trivial  
2. **iOS** — decode + `TodayFold` + mapper tests  
3. **iOS** — `InkVerdictPlate` / session card / overnight gauges (static previews)  
4. **iOS** — wire `TodayStore` + arrival director + replace current strip UI  
5. **QA** — live parity checklist  
6. **Later** — SwiftData snapshot

## 12. Risks

| Risk | Mitigation |
| --- | --- |
| Session sport/priority missing on VM | Ship null; UI degrades gracefully |
| Ink plate looks “alien” on light system chrome | Keep weather/nav system; plate is the single ink island (as web) |
| Scope creep into Plan vivant | Explicit non-goals; separate spec |

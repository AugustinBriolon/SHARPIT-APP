# iOS Design System Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a native-first Sharpit design system (tokens + components) and refactor Résumé to compose it so loading and loaded states share one instrument grammar.

**Architecture:** New `SHARPIT-APP/DesignSystem/` owns tokens and presentational components. Feature `Today` only composes them and handles screen state / networking. No third-party UI libs. File-system synchronized Xcode group picks up new files automatically.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, iOS 18+ deploy / iOS 27 simulator preferred for glass.

## Global Constraints

- English source / docs; French athlete-facing copy only.
- No SwiftUIX, CombineCocoa, or SwiftUICharts in this plan.
- Do not change `V1Today` DTOs or `GET /api/v1/today` contract.
- Verdict sits on canvas (no glass); session/signal plates use glass.
- Skeleton must mirror loaded structure (no opaque white hero block).
- Commits: Conventional Commits; only when asked or at end of each task if user requested commits — default: commit per task when executing this plan.
- Simulator signing stays `CODE_SIGN_IDENTITY=-` / `CODE_SIGNING_ALLOWED=YES` (Clerk Keychain).

---

## File map

| Path | Role |
| --- | --- |
| `SHARPIT-APP/DesignSystem/SharpitTheme.swift` | Spacing, typography, posture colors |
| `SHARPIT-APP/DesignSystem/SharpitGlass.swift` | Glass modifiers + nav/scroll chrome (moved) |
| `SHARPIT-APP/DesignSystem/SharpitEyebrow.swift` | Eyebrow label |
| `SHARPIT-APP/DesignSystem/VerdictHero.swift` | Verdict block |
| `SHARPIT-APP/DesignSystem/SessionPlate.swift` | One session plate |
| `SHARPIT-APP/DesignSystem/SignalStrip.swift` | Signal strip |
| `SHARPIT-APP/DesignSystem/SharpitLoadingInstrument.swift` | Loading skeleton |
| `SHARPIT-APP/DesignSystem/SharpitCanvasBackground.swift` | Posture gradient canvas |
| `SHARPIT-APP/Features/Today/TodayView.swift` | Compose design system only |
| Delete `SHARPIT-APP/Features/Today/SharpitGlass.swift` | After move |
| `SHARPIT-APPTests/SharpitThemeTests.swift` | Posture color + spacing smoke |

---

### Task 1: Theme tokens + unit test

**Files:**
- Create: `SHARPIT-APP/DesignSystem/SharpitTheme.swift`
- Create: `SHARPIT-APPTests/SharpitThemeTests.swift`

**Interfaces:**
- Produces: `enum SharpitSpacing`, `enum SharpitTypography`, `enum SharpitPostureStyle` with `static func color(for posture: V1TodayPosture) -> Color` and `static func canvasTop(for posture: V1TodayPosture?) -> Color`

- [ ] **Step 1: Write the failing test**

```swift
import SwiftUI
import Testing
@testable import Sharpit

@Test func postureProtectMapsToOrange() {
    #expect(SharpitPostureStyle.color(for: .protect) == Color.orange)
}

@Test func postureSteadyUsesAccent() {
    #expect(SharpitPostureStyle.color(for: .steady) == Color.accentColor)
}

@Test func canvasTopNilUsesAccentWash() {
    let top = SharpitPostureStyle.canvasTop(for: nil)
    #expect(top != Color.clear)
}

@Test func spacingPageInsetIs20() {
    #expect(SharpitSpacing.pageInset == 20)
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:SHARPIT-APPTests/SharpitThemeTests test
```

Expected: compile error `cannot find SharpitPostureStyle in scope` (or test target missing symbols).

- [ ] **Step 3: Implement theme**

```swift
import SwiftUI

enum SharpitSpacing {
    static let xxs: CGFloat = 8
    static let xs: CGFloat = 12
    static let sm: CGFloat = 14
    static let md: CGFloat = 16
    static let pageInset: CGFloat = 20
    static let section: CGFloat = 20
    static let lg: CGFloat = 28
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 24
}

enum SharpitTypography {
    static func eyebrow() -> Font { .system(size: 11, weight: .semibold) }
    static var eyebrowTracking: CGFloat { 1.6 }
    static func verdict() -> Font { .system(size: 36, weight: .semibold) }
    static var verdictTracking: CGFloat { -0.8 }
    static func label() -> Font { .system(size: 10, weight: .semibold) }
    static var labelTracking: CGFloat { 0.8 }
    static func data() -> Font { .title3.monospacedDigit().weight(.semibold) }
}

enum SharpitPostureStyle {
    static func color(for posture: V1TodayPosture) -> Color {
        switch posture {
        case .protect: .orange
        case .steady: Color.accentColor
        case .push: .green
        case .uncertain: .secondary
        }
    }

    static func canvasTop(for posture: V1TodayPosture?) -> Color {
        (posture.map(color(for:)) ?? Color.accentColor).opacity(0.18)
    }
}
```

- [ ] **Step 4: Run tests — expect PASS** for the four new tests (plus existing suite still green).

- [ ] **Step 5: Commit**

```bash
git add SHARPIT-APP/DesignSystem/SharpitTheme.swift SHARPIT-APPTests/SharpitThemeTests.swift
git commit -m "feat: add SharpitTheme tokens for posture and type"
```

---

### Task 2: Move glass + chrome into DesignSystem

**Files:**
- Create: `SHARPIT-APP/DesignSystem/SharpitGlass.swift` (content from `Features/Today/SharpitGlass.swift`, keep public API names)
- Delete: `SHARPIT-APP/Features/Today/SharpitGlass.swift`
- Create: `SHARPIT-APP/DesignSystem/SharpitEyebrow.swift` (move `SharpitEyebrow` out of glass file; use `SharpitTypography`)

**Interfaces:**
- Produces: `sharpitGlassCard()`, `sharpitGlassCapsule()`, `ScrollUnderGlass`, `LiquidNavChrome`, `SharpitEyebrow`
- Consumes: `SharpitTypography` from Task 1

- [ ] **Step 1: Write eyebrow style test (light)**

```swift
@Test func eyebrowUsesUppercaseTrackingContract() {
    #expect(SharpitTypography.eyebrowTracking == 1.6)
}
```

Add to `SharpitThemeTests.swift`.

- [ ] **Step 2: Run — PASS on tracking; then move files**

Implement `SharpitEyebrow`:

```swift
import SwiftUI

struct SharpitEyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(SharpitTypography.eyebrow())
            .tracking(SharpitTypography.eyebrowTracking)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}
```

Copy glass modifiers + `ScrollUnderGlass` + `LiquidNavChrome` into `DesignSystem/SharpitGlass.swift` unchanged functionally. Use `SharpitSpacing.cardRadius` in the rounded rect glass path.

Delete `Features/Today/SharpitGlass.swift`.

- [ ] **Step 3: Build**

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' build
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add SHARPIT-APP/DesignSystem SHARPIT-APP/Features/Today/SharpitGlass.swift SHARPIT-APPTests/SharpitThemeTests.swift
git commit -m "refactor: move glass and eyebrow into DesignSystem"
```

---

### Task 3: VerdictHero + SessionPlate + SignalStrip + Canvas

**Files:**
- Create: `SHARPIT-APP/DesignSystem/VerdictHero.swift`
- Create: `SHARPIT-APP/DesignSystem/SessionPlate.swift`
- Create: `SHARPIT-APP/DesignSystem/SignalStrip.swift`
- Create: `SHARPIT-APP/DesignSystem/SharpitCanvasBackground.swift`

**Interfaces:**
- Consumes: `V1TodayVerdict`, `V1TodaySession`, `V1TodaySignal`, `SharpitTheme`, glass, eyebrow
- Produces:
  - `VerdictHero(verdict: V1TodayVerdict)`
  - `SessionPlate(session: V1TodaySession)`
  - `SignalStrip(signals: [V1TodaySignal])`
  - `SharpitCanvasBackground(posture: V1TodayPosture?)`

- [ ] **Step 1: Implement components (no new network tests)**

`VerdictHero` — eyebrow, headline (`SharpitTypography.verdict`), subline, meta row (limitingCause + confidence). No glass.

`SessionPlate` — glass card; title/subtitle; kind label Faite/Prévue; metrics with data font.

`SignalStrip` — `SharpitEyebrow("Signaux")` + HStack of cells; map keys:

```swift
extension V1TodaySignalKey {
    var instrumentLabel: String {
        switch self {
        case .sleep: "Nuit"
        case .recovery: "Récup"
        case .effort: "Effort"
        case .adaptation: "Adapt."
        }
    }
}
```

Put `instrumentLabel` in `SignalStrip.swift` as fileprivate extension or in DesignSystem.

`SharpitCanvasBackground` — gradient `SharpitPostureStyle.canvasTop` → `Color(.systemBackground)`.

- [ ] **Step 2: Build**

Same `xcodebuild … build`. Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add SHARPIT-APP/DesignSystem
git commit -m "feat: add VerdictHero SessionPlate SignalStrip canvas"
```

---

### Task 4: Loading instrument + refactor TodayView

**Files:**
- Create: `SHARPIT-APP/DesignSystem/SharpitLoadingInstrument.swift`
- Modify: `SHARPIT-APP/Features/Today/TodayView.swift`

**Interfaces:**
- Consumes: all DesignSystem components from Tasks 1–3
- Produces: `TodayInstrumentView` composed of `VerdictHero` + `ForEach` `SessionPlate` + `SignalStrip`; loading uses `SharpitLoadingInstrument`

- [ ] **Step 1: Implement `SharpitLoadingInstrument`**

Mirror loaded layout: text skeleton for verdict (no fill card), glass for one session plate and four signal cells, `.redacted(reason: .placeholder)`, `ScrollUnderGlass`, page inset `SharpitSpacing.pageInset`.

- [ ] **Step 2: Refactor `TodayView`**

- `.loading` → `SharpitLoadingInstrument()`
- `.loaded` → `TodayInstrumentView` using design components only
- Background → `SharpitCanvasBackground(posture:)`
- Remove private duplicate `TodayLoadingView`, `TodayCanvasBackground`, local posture color extension, and inlined verdict/session/signal layout bodies

Keep `TodayController`, weather chip, unauthorized/failed/empty as today.

- [ ] **Step 3: Run full unit tests**

```bash
xcodebuild -project SHARPIT-APP.xcodeproj -scheme SHARPIT-APP \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' \
  -only-testing:SHARPIT-APPTests test
```

Expected: `TEST SUCCEEDED` (decoding + theme tests).

- [ ] **Step 4: Manual visual check**

Run on iPhone 17 / iOS 27: loading skeleton then fixture/live loaded — no white hero card; glass only on plates.

- [ ] **Step 5: Commit**

```bash
git add SHARPIT-APP/DesignSystem SHARPIT-APP/Features/Today/TodayView.swift
git commit -m "refactor: compose Today from DesignSystem components"
```

---

### Task 5: Spec/plan pointer in iOS README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add one Architecture bullet**

```markdown
- Design system: `SHARPIT-APP/DesignSystem/` (tokens + instrument components). Spec: `docs/superpowers/specs/2026-09-16-ios-design-system-design.md`
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: point README at iOS design system"
```

---

## Spec coverage

| Spec section | Task |
| --- | --- |
| Tokens color/type/spacing/surfaces | 1–2 |
| Components list | 3–4 |
| Résumé composition + loading | 4 |
| Testing | 1, 4 |
| Out of scope (no SwiftUIX/charts) | respected |
| README discoverability | 5 |

## Placeholder scan

None intentional. All APIs named above.

## Type consistency

- `SharpitPostureStyle.color(for:)` / `canvasTop(for:)` used by canvas + tests  
- `SharpitSpacing.pageInset` / `cardPadding` / `cardRadius` used by glass + loading + Today  
- `V1TodaySignalKey.instrumentLabel` used only by SignalStrip / loading

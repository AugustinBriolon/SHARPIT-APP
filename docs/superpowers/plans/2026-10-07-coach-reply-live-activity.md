# Coach Reply Live Activity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a local Live Activity when the athlete backgrounds SharpIt while the coach is answering, then flip to « Réponse prête » (short preview) when the answer is available.

**Architecture:** Shared `CoachReplyAttributes` + pure copy/preview helpers; app-side `CoachReplyLiveActivityController` started from `CoachView` on background+`isReplying`; ActivityKit UI in `SharpItWidgets`; local App Group preference with a Notifications switch. No APNs Live Activity push.

**Tech Stack:** Swift 6 · ActivityKit · WidgetKit · SwiftUI · Swift Testing · App Group `group.app.sharpit.ios`

## Global Constraints

- Spec: `docs/superpowers/specs/2026-10-07-coach-reply-live-activity-design.md`
- French product copy only on UI surfaces (titles/subtitles/settings)
- Artifacts (code comments, plan, tests names) in English
- One Live Activity at a time; start only on background while replying
- Deep link: `https://sharpit.app/coach` via `WidgetSnapshot.link("/coach")`
- No Cursor/AI attribution in commits
- Conventional Commits; commit only when the user asks

## File map

| File | Role |
| --- | --- |
| `SharpItShared/CoachReplyAttributes.swift` | Activity attributes + ContentState + preview/copy helpers |
| `SHARPIT-APPTests/CoachReplyLiveActivityTests.swift` | Pure helper + controller gate tests |
| `SharpItShared/CoachReplyLiveActivityPreference.swift` | App Group bool, default on |
| `SHARPIT-APP/Features/Coach/CoachReplyLiveActivityController.swift` | ActivityKit start/update/end |
| `SharpItWidgets/CoachReplyLiveActivity.swift` | Lock screen + Dynamic Island UI |
| `SharpItWidgets/SharpItWidgetsBundle.swift` | Register (Live Activities are discovered via ActivityConfiguration; bundle may only need the type linked) |
| `Config/Info-Extra.plist` | `NSSupportsLiveActivities` = true |
| `Config/SharpItWidgets-Info.plist` | Same key if required for extension |
| `SHARPIT-APP/Features/Coach/CoachView.swift` | Background start + wire controller |
| `SHARPIT-APP/Features/Coach/CoachStore.swift` | Callbacks markReady / markFailed |
| `SHARPIT-APP/Features/Settings/SettingsPages.swift` | Notifications toggle |

---

### Task 1: Shared attributes + copy/preview helpers

**Files:**
- Create: `SharpItShared/CoachReplyAttributes.swift`
- Create: `SHARPIT-APPTests/CoachReplyLiveActivityTests.swift`

**Interfaces:**
- Produces: `CoachReplyAttributes`, `CoachReplyAttributes.ContentState`, `CoachReplyAttributes.Phase`, `CoachReplyPreview.line(from:max:)`, `CoachReplyLiveActivityCopy.subtitle(phase:preview:)`

- [ ] **Step 1: Write failing tests for preview truncation and French subtitles**

```swift
import Testing
@testable import Sharpit

@Test func previewKeepsAShortLineAndCapsLongOnes() {
    #expect(CoachReplyPreview.line(from: "  Oui.  ") == "Oui.")
    let long = String(repeating: "a", count: 120)
    let line = CoachReplyPreview.line(from: long)
    #expect(line.count <= 80)
    #expect(line.hasSuffix("…"))
}

@Test func subtitleMatchesPhase() {
    #expect(CoachReplyLiveActivityCopy.subtitle(phase: .replying, preview: "") == "Répond…")
    #expect(CoachReplyLiveActivityCopy.subtitle(phase: .ready, preview: "") == "Réponse prête")
    #expect(CoachReplyLiveActivityCopy.subtitle(phase: .ready, preview: "TSB +4") == "Réponse prête · TSB +4")
    #expect(CoachReplyLiveActivityCopy.subtitle(phase: .failed, preview: "") == "Réponse interrompue · rouvre SharpIt")
}
```

- [ ] **Step 2: Run tests — expect FAIL (types missing)**

Run: `xcodebuild test -scheme SHARPIT-APP -destination 'platform=iOS Simulator,id=698B17DC-CEA7-4877-A4D7-4DD898D38514' -only-testing:SHARPIT-APPTests/CoachReplyLiveActivityTests`

- [ ] **Step 3: Implement shared types**

```swift
import ActivityKit
import Foundation

public struct CoachReplyAttributes: ActivityAttributes {
    public var conversationId: String

    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: Phase
        public var preview: String

        public init(phase: Phase, preview: String = "") {
            self.phase = phase
            self.preview = preview
        }
    }

    public enum Phase: String, Codable, Hashable, Sendable {
        case replying, ready, failed
    }

    public init(conversationId: String) {
        self.conversationId = conversationId
    }
}

public enum CoachReplyPreview {
    public static let maxLength = 80

    public static func line(from text: String, max: Int = maxLength) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > max else { return collapsed }
        let end = collapsed.index(collapsed.startIndex, offsetBy: max - 1)
        return String(collapsed[..<end]) + "…"
    }
}

public enum CoachReplyLiveActivityCopy {
    public static let title = "Coach"

    public static func subtitle(phase: CoachReplyAttributes.Phase, preview: String) -> String {
        switch phase {
        case .replying: return "Répond…"
        case .ready:
            return preview.isEmpty ? "Réponse prête" : "Réponse prête · \(preview)"
        case .failed: return "Réponse interrompue · rouvre SharpIt"
        }
    }
}
```

- [ ] **Step 4: Re-run tests — expect PASS**

---

### Task 2: Local preference

**Files:**
- Create: `SharpItShared/CoachReplyLiveActivityPreference.swift`
- Modify: `SHARPIT-APPTests/CoachReplyLiveActivityTests.swift`
- Modify: `SHARPIT-APP/Features/Settings/SettingsPages.swift` (toggle in `kinds`)

**Interfaces:**
- Produces: `CoachReplyLiveActivityPreference.isEnabled` / `setEnabled(_:)` on App Group suite

- [ ] **Step 1: Preference type + test default on**

```swift
public enum CoachReplyLiveActivityPreference {
    public static let key = "coachReplyLiveActivity"
    private static var suite: UserDefaults {
        UserDefaults(suiteName: "group.app.sharpit.ios") ?? .standard
    }

    public static var isEnabled: Bool {
        if suite.object(forKey: key) == nil { return true }
        return suite.bool(forKey: key)
    }

    public static func setEnabled(_ on: Bool) {
        suite.set(on, forKey: key)
    }
}
```

- [ ] **Step 2: Add Notifications toggle**

In `NotificationPrefsView.kinds`, after session toggles:

```swift
Toggle(isOn: Binding(
    get: { CoachReplyLiveActivityPreference.isEnabled },
    set: { CoachReplyLiveActivityPreference.setEnabled($0) }
)) {
    Label {
        VStack(alignment: .leading, spacing: 2) {
            Text("Live Activity coach")
                .font(SharpitTypography.bodyEmphasis)
            Text("Sur l'écran verrouillé pendant que le coach répond.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    } icon: {
        SharpitRowIcon(symbol: "platter.filled.top.and.arrow.up.iphone")
    }
}
.tint(SharpitColor.primary)
```

---

### Task 3: Controller (ActivityKit) + gate tests

**Files:**
- Create: `SHARPIT-APP/Features/Coach/CoachReplyLiveActivityController.swift`
- Modify: `SHARPIT-APPTests/CoachReplyLiveActivityTests.swift`

**Interfaces:**
- Produces: `@MainActor final class CoachReplyLiveActivityController` with `startIfNeeded(conversationId:isReplying:)`, `markReady(preview:)`, `markFailed()`, `end()`
- Gate helper: `CoachReplyLiveActivityGate.shouldStart(isReplying:preferenceEnabled:activitiesEnabled:)`

- [ ] **Step 1: Tests for gate**

```swift
@Test func startsOnlyWhenReplyingAndEnabled() {
    #expect(CoachReplyLiveActivityGate.shouldStart(
        isReplying: true, preferenceEnabled: true, activitiesEnabled: true
    ))
    #expect(!CoachReplyLiveActivityGate.shouldStart(
        isReplying: false, preferenceEnabled: true, activitiesEnabled: true
    ))
    #expect(!CoachReplyLiveActivityGate.shouldStart(
        isReplying: true, preferenceEnabled: false, activitiesEnabled: true
    ))
}
```

- [ ] **Step 2: Implement controller**

Use `Activity<CoachReplyAttributes>.request` / `update` / `end`. Store current `Activity` weakly/optionally. On `markReady`, update then `Task { try? await Task.sleep(for: .seconds(4)); await end() }`. Invalidate dwell Task on new start.

---

### Task 4: Widget Live Activity UI + Info.plist

**Files:**
- Create: `SharpItWidgets/CoachReplyLiveActivity.swift`
- Modify: `Config/Info-Extra.plist` — add `NSSupportsLiveActivities` = true
- Modify: `Config/SharpItWidgets-Info.plist` — same if not inherited

- [ ] **Step 1: ActivityConfiguration**

Lock screen + Dynamic Island compact/expanded using `CoachReplyLiveActivityCopy` and `WidgetSnapshot.link("/coach")`. Minimal Sharpit styling (eyebrow + body), no typing dots.

- [ ] **Step 2: Ensure attributes type is linked into the widget target** (already via SharpItShared sync group)

---

### Task 5: Wire CoachView + CoachStore

**Files:**
- Modify: `SHARPIT-APP/Features/Coach/CoachView.swift`
- Modify: `SHARPIT-APP/Features/Coach/CoachStore.swift`

**Interfaces:**
- Consumes: `CoachReplyLiveActivityController.shared`
- Store optional callback or direct calls: on successful stream end → `markReady`; on cancel path after resync → `markReady`; on hard error → `markFailed`

- [ ] **Step 1: CoachView `scenePhase` → background**

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .background {
        CoachReplyLiveActivityController.shared.startIfNeeded(
            conversationId: store.conversationId ?? "",
            isReplying: store.isReplying
        )
    }
    if phase == .active {
        Task { await store.resumeAfterInterruption() }
    }
}
```

- [ ] **Step 2: CoachStore after successful answer**

After stream with content: `CoachReplyLiveActivityController.shared.markReady(preview: CoachReplyPreview.line(from: assembler.text))`  
On `CancellationError` path: leave to resync; in `resyncFromServer` success call `markReady` from last assistant text.  
On hard failure: `markFailed()`.  
On `startNewConversation`: `end()`.

- [ ] **Step 3: Build + run CoachReplyLiveActivityTests + CoachHistoryTests**

---

### Task 6: Manual smoke

- [ ] Send coach message → background → Island « Répond… »
- [ ] Wait → « Réponse prête » → tap → Coach tab
- [ ] Preference off → no activity
- [ ] Kill mid-stream → reopen → thread resyncs; activity ends/ready once

---

## Spec coverage check

| Spec item | Task |
| --- | --- |
| Start on background + replying | 5 |
| Phases replying/ready/failed | 1, 3 |
| Preview cap | 1 |
| Preference + settings | 2 |
| Widget UI + deep link | 4 |
| Resync → ready | 5 |
| No push / no pre-session | — out of scope |

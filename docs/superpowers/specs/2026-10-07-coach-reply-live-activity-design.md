# Coach reply Live Activity — iOS design

Status: accepted — 2026-10-07 (implemented).

## Why

When the athlete sends a coach message and leaves the app, the SSE stream is often cut on the
client while the server keeps writing and saves the answer. The thread already resyncs on return
(`CoachStore.resumeAfterInterruption`). What is missing is a lock-screen / Dynamic Island signal
that the turn is still running, then that the answer is ready — without opening SharpIt.

Out of scope for this delivery: pre-session countdown, race-week, plan/adapt job Live Activities,
and APNs push updates to Live Activities.

## Behaviour

| Moment | Display |
| --- | --- |
| App backgrounds while `CoachStore.isReplying` | Start Live Activity — phase `replying` |
| Stream finishes successfully, or `resyncFromServer` succeeds | Update — phase `ready` + short preview |
| Stream fails (non-cancel), or resync never recovers | Update — phase `failed` |
| Tap | Open `https://sharpit.app/coach` (existing `IncomingLink` → Coach tab) |
| ~3–5 s after `ready` / `failed`, or athlete dismisses | End the activity |
| Preference off, or system Live Activities disabled | Do not start |

Rules:

- At most one coach-reply Live Activity at a time.
- Do **not** start while the app stays in the foreground — only when leaving during a reply.
- Keep the partial bubble in the app; the Live Activity does not own history.
- Preview is one short line of plain text (trim / collapse whitespace, cap ~80 characters). Empty
  preview is allowed on `ready` (« Réponse prête » alone).

## Preference

- One Sharpit switch under Notifications: **Live Activity coach** (default on).
- Stored locally (App Group `group.app.sharpit.ios`, same family as widget prefs) so the extension
  does not need a network read.
- iOS Settings → Live Activities remains the system kill switch; honour `ActivityAuthorizationInfo`.

## Architecture

### Shared — `CoachReplyAttributes` (`SharpItShared`)

```text
Attributes
  conversationId: String   // "" when the turn is not yet stored

ContentState
  phase: replying | ready | failed
  preview: String          // empty unless phase == ready
```

### Widget extension — `CoachReplyLiveActivity`

- `ActivityConfiguration` in `SharpItWidgets` (alongside existing widgets).
- Lock screen + Dynamic Island (compact leading/trailing minimal; expanded = same copy as lock).
- Visual language: Sharpit canvas cues already used by widgets — no chatbot chrome, no typing dots.
- `widgetURL` / open URL: `WidgetSnapshot.link("/coach")`.

### App — `CoachReplyLiveActivityController`

Owned by the app target; called from `CoachView` / `CoachStore` edges:

| Hook | Action |
| --- | --- |
| `scenePhase` → `.background` and `isReplying` and preference on | `startIfNeeded(conversationId:)` |
| Stream ends with content | `markReady(preview:)` |
| `resyncFromServer` succeeds after interruption | `markReady(preview:)` from last assistant text |
| Hard failure (not cancel) | `markFailed()` |
| After ready/failed dwell, or `startNewConversation` | `end()` |

Implementation notes:

- Use `Activity.request` / `activity.update` / `activity.end` (ActivityKit).
- No push token registration in v1 (`NSSupportsLiveActivities` in Info.plist only).
- If `ActivityAuthorizationInfo().areActivitiesEnabled` is false, no-op.
- Unit-test the pure mapping: phase transitions + preview truncation (no ActivityKit in tests).

### Deep link

v1 opens the Coach tab only (`/coach`). The in-memory `CoachStore` already holds the open
conversation after resync; opening a specific `conversationId` from the URL is a later
enhancement if cold-start races appear.

## Copy (French, product voice)

| Phase | Title | Subtitle |
| --- | --- | --- |
| `replying` | Coach | Répond… |
| `ready` | Coach | Réponse prête · {preview} — or « Réponse prête » if no preview |
| `failed` | Coach | Réponse interrompue · rouvre SharpIt |

Settings switch:

- Label: Live Activity coach  
- Detail: Sur l’écran verrouillé pendant que le coach répond.

## Testing

- Unit: preview truncation; controller state machine (start only if replying + enabled; ready/failed/end).
- Manual: send → background → Island shows « Répond… » → wait → « Réponse prête » → tap → Coach.
- Manual: send → background → kill app → reopen → resync fills thread; activity ends or shows ready once.
- Manual: preference off → no activity.

## Non-goals (explicit)

- Pre-session / race Live Activities  
- Server-driven Live Activity push updates  
- Showing the full coach answer on the lock screen  
- Starting the activity at `send()` while still foreground  

# 18. Cold launch holds one splash until the landing screen is ready

Date: 2026-10-18

## Status

Accepted

## Context

A signed-in athlete opening the app cold went through two loading states in a row:
`AccountGate` showed `SharpitLaunchMark` while its status was `.checking`, then Résumé appeared
and showed its own skeleton (`SharpitLoadingInstrument`) until `TodayStore` left `.loading` —
even when a cached SwiftData snapshot was on disk, because the snapshot is only read from the
view's `.task`, after the first frame. The athlete saw a mark, a cut, a skeleton, then a second
cut to the day, and Résumé's arrival reveal sometimes ran while nothing was settled.

The splash cannot be the system launch screen: that one is static and cannot wait on data.
It also must never trap the athlete: the network can be slow or absent, and the app works
offline from the cache.

## Decision

We hold one loading screen, `SharpitLaunchSplash`, over the whole app on a cold launch,
controlled by `LaunchCurtain` (owned by `SharpitApp`, one per process, passed through the
environment).

- The curtain lifts once the landing screen can be drawn whole: Résumé's read answered (success
  or failure), or the sign-in screen, the consent wall, the onboarding wizard, the
  gate's failure screen, or another tab opened by a link or a notification. Each of these
  surfaces calls `markReady()`.
- It stays up at least 0.6 s (none under Reduce Motion), so a fast launch does not flicker, and
  at most 3.5 s, after which it lifts whatever the network is doing.
- While up, the mark only breathes; no spinner. It leaves with a fade and an 8 % grow
  (`AnyTransition.sharpitLaunchExit`) on a critically damped spring (response 0.35 s), through
  `SharpitMotion.run`, so Reduce Motion swaps it without animation. An orbiting-dots loader
  that closed into a dot and burst open onto Résumé was tried and dropped as too busy. Résumé's arrival
  (`TodayArrivalDirector`) waits for the lift, so it plays during the hand-over.
- A return from the background never shows it again.
- The cached snapshot does not lift it: it holds the verdict plate without sessions or gauges, so
  lifting on it showed a half-filled Résumé. It still paints Résumé when the ceiling is reached.
- The system launch screen (`UILaunchScreen`) draws the same mark on the canvas colour
  (`LaunchMark`, rendered on iOS from `SharpitLaunchSplash.mark`; `LaunchBackground`), and the
  splash centres its mark on the screen rather than the safe area, so the hand-over from iOS to
  the app shows the mark without a blank or a jump. The mark is visible from the splash's first
  frame: a cold Debug launch keeps the main thread busy for about 2 s, which froze a fade-in at
  zero opacity.

## Options considered

### Option A — Keep the gate's mark and Résumé's skeleton

No new code. Two loading states, two cuts, and the skeleton shows even when the snapshot is on
disk. This is the behaviour the athlete asked to replace.

### Option B — Block on the network until Résumé is read, with no timeout

Résumé would always appear complete, but a slow server or no connection would leave the athlete
on the splash indefinitely, while the cache could have painted the day at once.

### Option C — One splash gated on readiness, with a floor and a ceiling (chosen)

One continuous loading screen and one transition. The 3.5 s ceiling bounds the worst case: past
it, Résumé shows the cached day, or its own loading or failure state. Costs a
small observable model and a `markReady()` call in each surface that can be the landing screen.

## Consequences

### Positive
- A cold launch goes launch screen → splash → a complete Résumé, with no blank and no skeleton frame.
- The worst-case wait on the splash is 3.5 s; offline, the cached day shows then.
- The readiness rules live in one testable type (`LaunchCurtainTests`).

### Negative
- A fast launch now waits at least 0.6 s on the splash.
- A new screen that can be the landing screen must call `markReady()`, or the launch waits for
  the 3.5 s ceiling.
- An offline launch waits the full 3.5 s ceiling unless the read fails sooner.
- `LaunchMark` is a rendered copy of an SF Symbol: a change to the mark means re-rendering it.

### Neutral
- `SharpitLaunchMark` stays for the gate's later checks (a retry) and the wizard's first read.
- The launch screen follows the system appearance, not the in-app appearance setting.

## References
- `SHARPIT-APP/App/LaunchCurtain.swift`, `SHARPIT-APP/DesignSystem/SharpitLaunchSplash.swift`

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

- The curtain lifts once the landing screen can be drawn whole: Résumé out of `.loading` (the
  cached snapshot counts), or the sign-in screen, the consent wall, the onboarding wizard, the
  gate's failure screen, or another tab opened by a link or a notification. Each of these
  surfaces calls `markReady()`.
- It stays up at least 0.6 s (none under Reduce Motion), so a fast launch does not flicker, and
  at most 3.5 s, after which it lifts whatever the network is doing.
- It leaves with a fade and a 6 % grow (`AnyTransition.sharpitLaunchExit`), through
  `SharpitMotion.run`, so Reduce Motion swaps it without animation. Résumé's arrival
  (`TodayArrivalDirector`) waits for the lift, so it plays during the hand-over.
- A return from the background never shows it again.

## Options considered

### Option A — Keep the gate's mark and Résumé's skeleton

No new code. Two loading states, two cuts, and the skeleton shows even when the snapshot is on
disk. This is the behaviour the athlete asked to replace.

### Option B — Block on the network until Résumé is read, with no timeout

Résumé would always appear complete, but a slow server or no connection would leave the athlete
on the splash indefinitely, while the cache could have painted the day at once.

### Option C — One splash gated on readiness, with a floor and a ceiling (chosen)

One continuous loading screen and one transition. The cache counts as ready, and the 3.5 s
ceiling bounds the worst case: past it, Résumé's own loading or failure state takes over. Costs a
small observable model and a `markReady()` call in each surface that can be the landing screen.

## Consequences

### Positive
- A cold launch with a cached day goes splash → Résumé in one transition, with no skeleton frame.
- The worst-case wait on the splash is 3.5 s; offline launches with a cache are not slowed.
- The readiness rules live in one testable type (`LaunchCurtainTests`).

### Negative
- A fast launch now waits at least 0.6 s on the splash.
- A new screen that can be the landing screen must call `markReady()`, or the launch waits for
  the 3.5 s ceiling.

### Neutral
- `SharpitLaunchMark` stays for the gate's later checks (a retry) and the wizard's first read.
- The system launch screen is still the generated one; its colour is not matched to the canvas.

## References
- `SHARPIT-APP/App/LaunchCurtain.swift`, `SHARPIT-APP/DesignSystem/SharpitLaunchSplash.swift`

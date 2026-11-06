# 30. A guided strength session runs above the tabs

Date: 2026-11-06

## Status

Accepted

## Context

The guided strength session (`GuidedStrengthWorkoutView`) was a full-screen cover presented by the session drawer, and all of its state lived in the view: the sets, the rest, the clock and the heart rate. The athlete reported three problems:

- « Terminer » went straight to the summary, with no way back to the sets.
- The only way out was « Quitter sans enregistrer ». Checking something in another tab meant losing the session.
- Holds had no timer. A stretch done one side then the other (hip flexors) read as « 3 répétitions » or « 1 × 0 kg ». SHARPIT ADR-121 fixes the data (`perSide`, holds, no load); the guided session has to follow it.

## Decision

- **Reduce.** A session is run by the app, not by the screen that started it. `GuidedWorkoutDock`, owned by `RootView` and placed in the environment, holds the one running session. `GuidedWorkoutDockHost` mounts the same view over the tabs. « Réduire la séance », a ⌄ button beside « Quitter » and on every pushed page, slides it off screen without removing it, so the sets, rest, clock, heart rate and Live Activity keep running. The tab bar's bottom accessory (`tabViewBottomAccessory`, iOS 26.1; before that, a glass capsule above the tabs) shows « Push day · 12:34 », and a tap brings the session back. « Lancer la séance » closes the drawer and hands the session to the dock. A second launch brings back the session already running instead of replacing it. Saving or quitting ends it. Hosts with no dock keep the plain cover.
- **Resume.** The summary carries « Reprendre la séance », which goes back to the sets with nothing lost.
- **Hold by side.** A hold set has a play button that pushes `GuidedHoldPage`. It runs « Mets-toi en place » (5 s), then the hold. For a `perSide` set it runs « Côté gauche », then « Change de côté » (5 s, to switch legs without eating into the second side), then « Côté droit ». The whole sequence shows from the start (« Gauche · 30 s  Droite · 30 s »), and each step says what comes next (« Ensuite : côté droit, 30 s »), so the second countdown is never a surprise. A sound marks each new step and the last three seconds of each step. There is no haptic: the phone is on the floor, and the app keeps haptics for a notch under the finger. VoiceOver announces each step, and the screen stays awake. The button moves forward one step at a time: « Commencer », then « Passer au côté droit », and on the last side « Terminer la série », which ticks the set. The set is also ticked when the last countdown ends. One set covers both sides, so 3 sets means three times each side. `GuidedHoldClock` derives the step from the elapsed time and is unit-tested. Set lines say « par côté » and never show a 0 kg load.

## Options considered

### Option A — Move the session's state into an app-level store

The view would only render the store. It is the « clean » shape, but it means rewriting the 1,100-line view and its timers, rest and heart-rate handling, which carries a high risk of regression for the same behaviour.

### Option B — Keep the same view alive in an overlay above the tabs (chosen)

The view's state survives because the view is never removed. The change touches its launch and its closing only. Cons: the session is still lost if iOS kills the app, as before. The overlay sits under any sheet, which is why launching closes the drawer first.

### Option C — Ask once per hold set whether to time each side (two rows per set)

It is more explicit, but it doubles the list and the ticks for one movement. Strength apps run both sides inside one set.

## Consequences

### Positive

- The athlete can leave a session to look at the plan or the coach and come back to it running.
- « Terminer » can be undone. A stretch reads, and is timed, as it is done.

### Negative

- A reduced session is lost if the app is killed. Persisting it is a separate change.
- The accessory before iOS 26.1 clears the tab bar by a fixed height.

### Neutral

- The Live Activity for rest is unchanged. It still runs while the session is reduced.

## References

- `Features/Plan/GuidedStrength/GuidedWorkoutDock.swift`, `GuidedHoldPage.swift`
- SHARPIT ADR-121 (strength set shape)

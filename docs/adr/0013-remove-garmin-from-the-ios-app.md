# 0013. Remove Garmin from the iOS app

Date: 2026-10-17

## Status

Accepted

## Context

Garmin's API access is unofficial and its developer program takes no new applications. App Review
guideline 5.2.2 asks for permission to use a third-party service, so a build that connects Garmin
risks a rejection that would block the launch (the same reasoning as `docs/adr/0010` for
MyFitnessPal).

Until now the app kept the integration behind `ProviderAvailability.garminInApp`, true only in
DEBUG builds. The flag did not cover everything: in Release builds the strength session's
« Envoyer à la montre », Seuils' « Importer depuis Garmin » and the full-history import run on launch
were still reachable or running, which contradicted the Beta App Review notes (« pas de connexion
Garmin dans l'app »).

Garmin watches still reach SHARPIT two ways that need nothing from the app: Garmin Connect writes
to Apple Health, which the app reads, and an account linked on the web keeps syncing server-side.

## Decision

We delete every Garmin integration from the iOS app: the connect flow (handoff, OAuth return
link, onboarding card, Sources row and disconnect), the full-history import, the threshold import,
the workout push from Plan and from a done strength session, the « Sur la montre Garmin » badges and
the `garminWorkout*` fields of planned sessions. `theAppNeverLinksGarmin` fails the build's tests if
a Garmin route comes back into the app target.

Data that came from Garmin through the server is still shown with its source when the payload
names it (a body metric « Garmin », the HRV band « selon Garmin »): that is a fact about the data,
not an integration. Threshold wording no longer names Garmin (« Synchronisé depuis ta montre »).

## Options considered

### Option A — Keep the DEBUG flag and close the leaks

Gate the three remaining surfaces behind `ProviderAvailability`. Pros: one flag turns Garmin back
on the day access is official; the developer keeps testing it in Xcode. Cons: the code stays in the
binary Apple reviews, the flag has already leaked once, and every new Garmin surface has to remember
it.

### Option B — Delete the integration (chosen)

Pros: nothing Garmin ships, so Review cannot find it; about 1 300 lines and their tests go; a
source scan test keeps it out. Cons: bringing Garmin back means restoring it from git history;
an athlete can no longer push a session to the watch or disconnect Garmin from the phone (the web
still does both).

## Consequences

### Positive
- The App Store build has no unofficial third-party integration left.
- The Sources page, onboarding and Plan drawer lose a branch each; the Beta App Review notes are
  true again.

### Negative
- Workout push to the watch is web-only until Garmin access is official.
- A Garmin account linked on the web is not listed in Sources on the phone and is disconnected on
  the web.

### Neutral
- Supersedes the DEBUG-only part of `docs/adr/0005` and the `ProviderAvailability` reference in
  `docs/adr/0010`.
- The `Provider/Garmin` logo stays for source labels the server sends.

## References
- App Review Guidelines 5.2.2
- `docs/adr/0005-app-started-sync-and-apple-health.md`, `docs/adr/0010-import-the-myfitnesspal-export-instead-of-linking-it.md`
- `docs/beta-testflight.md`

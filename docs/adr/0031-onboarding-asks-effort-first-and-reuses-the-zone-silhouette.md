# 31. Onboarding asks effort first and reuses the zone silhouette

Date: 2026-11-09

## Status

Accepted

## Context

Feedback from a field test of the onboarding, focused on athletes without a watch, whose answers are all the coach knows about them before any data arrives:

- Matériel (step 4) read as a prerequisite: « Vélo outdoor » or « Accès piscine » looked like conditions for doing the sport, not extras. Continue already worked with nothing ticked.
- Ta semaine (step 5) only asked for days, painted with a finger. The bars' run and sleep icons read as a movement to perform, and the athlete could not say how hard they wanted the weeks to be.
- Objectif (step 6) offered a race or a figure. « Garder la forme » and « être régulier » had nowhere to go.
- Blessures (step 7) had 13 zones while the web lists 23 (no elbow, no wrist). A healed but fragile injury could not be told apart from a current one, and health conditions with no zone (osteoporosis, water retention, the menstrual cycle) had nowhere to go.

## Decision

- **Matériel** is titled « En plus, si tu as » and says that with nothing ticked the coach plans outdoor sessions without equipment.
- **Ta semaine** asks for the intensity first (Tranquille, Régulier, Soutenu, Intensif). The intensity seeds a session count (2, 3, 4, 5) that a stepper moves from 1 to 7. Then the athlete picks exactly that many days: the store refuses a day beyond the count, and Continue waits until the count is met. The bars are a plain fill. The intensity is sent as `trainingAvailability.intensity` (SHARPIT ADR-123).
- **Objectif** offers a third kind, `HABIT` (« Garder la forme »), with no date and no figure (SHARPIT ADR-123). The Objectifs form offers it too, with only its name.
- **Corps** draws the Santé silhouette (`SensitiveZoneBodyMap`, a man's or a woman's figure from the declared sex, every part of the web's list). A tap opens the zone's sheet on the side touched, and its questions come one after another: what it is (douleur, blessure en cours, ancienne blessure encore fragile), the side, then how much it bothers. A fragile zone has no level and is written as `INJURY` with status `MONITORING`. Under the body, « Un terrain à ménager ? » offers osteoporosis and water retention, the menstrual cycle only to a woman, and a free « Autre ». Each is written as an `OTHER` note with no body part, under watch. Both kinds are drafts like the injuries, so they wait for the health consent and are replayed after sign-up with no new plumbing.

## Options considered

### Option A — A profile field for health conditions

This is cleaner for later work (the cycle from HealthKit), but it needs a migration and a new coach context section. Physical notes already reach the generator (`getTrainingZoneNotes` reads `MONITORING`) and the athlete's Santé page.

### Option B — Physical notes (chosen)

## Consequences

- The onboarding's own zone list is gone. `OnboardingInjuryDraft.bodyParts` derives from `SensitiveZoneBody`, so it cannot drift from the map again.
- An app older than this build cannot decode a `HABIT` goal. The server migration must ship before this build reaches anyone.
- The web's availability picker still asks for days only and writes no intensity.

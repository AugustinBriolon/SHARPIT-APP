# 37. Every exercise shows its Gym Visual picture

Date: 2026-11-24

## Status

Accepted. The licence question below is open and must be settled before the next App Store submission.

## Context

The guided strength session already showed each exercise's still and animated demonstration, read
from the bundled `exercises-media-index.json` (1,324 exercises, ids and media ids, 111 French
aliases) and served as `images/{id}-{mediaId}.jpg` and `videos/{id}-{mediaId}.gif` from a jsDelivr
mirror of a public GitHub dataset. The pictures are Gym Visual's (`© Gym visual — gymvisual.com`).
The exercise picker and the progression page showed none: the athlete asked for the same picture
on every exercise list, and whether the library would be enough if the app relied on it alone.

## Decision

We will draw every exercise from this one catalog wherever it is listed: the picker's rows carry
the still (`GuidedExerciseThumbView`, the strength glyph when the catalog has no match), the
progression page opens on the animated demonstration with its attribution line. No second source.

## Options considered

### Option A — The existing Gym Visual catalog everywhere (chosen)

- Pros: no new data, no new dependency, one look across the guided session, the picker and the
  progression; 1,324 exercises cover the movements the coach prescribes.
- Cons: the media are hotlinked from a third-party mirror of a commercial library, with no licence
  on record; the mirror can disappear and the rights are not established.

### Option B — Buy the Gym Visual licence and self-host

- Pros: settles the rights; Gym Visual's full library (thousands more exercises) becomes available.
- Cons: a cost and an upload pipeline before anything ships.

### Option C — Switch to free-exercise-db (public domain, ~800 exercises)

- Pros: no licence question.
- Cons: fewer exercises, photographs of uneven style beside the Gym Visual drawings already shipped.

## Consequences

### Positive

- An exercise reads the same picture in the picker, the session and its progression.

### Negative

- The licence gap is now visible on more screens. Before the next submission, either a Gym Visual
  licence is bought and the media self-hosted (Option B), or the source is replaced.

### Neutral

- The catalog stays the bundled index; adding Gym Visual's larger library is a data change, not a
  code one.

## References

- `SHARPIT-APP/Features/Plan/GuidedStrength/ExerciseMediaCatalog.swift`
- `SHARPIT-APP/Features/Plan/GuidedStrength/ExercisePickerSheet.swift`
- `SHARPIT-APP/Features/Plan/GuidedStrength/ExerciseProgressionPage.swift`

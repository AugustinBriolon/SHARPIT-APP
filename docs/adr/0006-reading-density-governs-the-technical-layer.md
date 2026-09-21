# 6. Reading density governs the technical layer

Date: 2026-09-21

## Status

Accepted

## Context

The web has a per-athlete reading density, `displayMode`, with two values: `essential` and
`expert`. It is stored on the athlete profile rather than on the device, so it follows the
athlete across phone, tablet and desktop, and `essential` is the default for an athlete who
never chose. `essential` is the accessible reading — what happened, how it felt, what to do
next. `expert` adds the technical layer those readings were derived from: TSS, IF,
CTL/ATL/TSB, thresholds, zones, decoupling.

The app has never read it. Every screen renders one reading, and where a technical number was
awkward the app dropped it: `PlannedSessionPreview.init(session:)` states that
"Charge/TSS is deliberately absent — a planning number, not something the athlete acts on
before a session". That was a reasonable call for a client with no density — better to omit a
number than to show an athlete an acronym they cannot use. It is the wrong call for a client
that knows who is reading.

Moi now reads `/api/athlete-profile`, which carries `displayMode`. Adding the picker without
deciding what it governs would ship a preference that changes nothing.

The web draws the line in two different ways, and the distinction matters:

- `ExpertOnly` hides a whole block from the essential reading. Nothing is fetched or computed
  differently; the block is simply not rendered.
- `formatTrainingLoad(load, mode)` shows the load in **both** readings and changes only the
  word: `charge 78` in essential, `78 TSS` in expert. The magnitude is not the barrier — the
  acronym is.

Session load falls in the second category on the web, on the activity detail, the plan
projection, the week summary and the planned session. The app currently shows it in neither.

## Decision

- A `DisplayModeStore` in the environment holds the density, read from `/api/athlete-profile`
  through `AthleteProfileStore`. Moi offers the picker, which saves on the tap with no form
  to submit, as the web's Personnalisation does.
- Until the profile answers, the app renders the **essential** reading. A technical number
  that flashes in and then disappears is worse than one that arrives a moment late.
- Session load becomes visible in both readings, in the web's own words:
  `charge 78` in essential and `78 TSS` in expert, on the activity detail and in the planned
  session drawer. This reverses the omission recorded at `PlannedSessionDrawer.swift:34`.
- Anything the athlete cannot act on without the vocabulary — IF, CTL/ATL/TSB, zone
  distributions, decoupling — is shown in the expert reading only, and simply absent
  otherwise. No teaser, no lock, no "passe en expert" prompt.
- The density chooses what is shown and how it is named. It never changes what is measured,
  what is fetched, or what the coach is told. A screen must render correctly in both
  readings from the same payload.
- The density is not an access tier. `tier` (FREE / PRO) gates features; the density is a
  reading preference and gates nothing.

## Options considered

### Option A — Leave the app on one reading
No picker, no density. Cons: the athlete's own preference, set on the web, is ignored on the
phone; the app keeps hiding numbers the web shows, and the two clients keep diverging.

### Option B — Expert reveals the technical layer, load shown in both (chosen)
Mirrors `ExpertOnly` and `formatTrainingLoad` exactly, so a number reads the same on both
platforms. The magnitude of a session's load reaches every athlete; the acronym reaches the
ones it means something to. Cons: two wordings to keep in step with the web; every surface
that shows load has to ask the store.

### Option C — Expert gates the load entirely
Simpler: one rule, hide or show. Cons: contradicts the web, where the load is in the
essential reading. An athlete would see `charge 78` on the web and nothing in the app, and
would reasonably read that as a bug.

### Option D — A device-local switch in Moi
No network read, instant. Cons: the density belongs to the athlete, not to the handset;
choosing expert on the phone would leave the web essential, and the app would own a second
source of truth for a value the profile already holds.

## Consequences

### Positive
- An athlete who chose expert on the web sees the same reading on the phone.
- Session load stops being invisible in the app: a planned session states its charge before
  the athlete trains, which is what the plan projection already does on the web.
- New technical readouts have a home. A metric no longer has to be dropped for being too
  technical; it is placed in the expert reading.

### Negative
- Every surface that shows a technical figure now depends on the store, so a screen has two
  renderings to check rather than one.
- The load wording is duplicated from the web's `formatTrainingLoad`. If the web changes
  `charge` to another word, the app will not follow on its own.
- One more thing the first paint waits on: before the profile answers, an expert athlete
  briefly gets the essential reading.

### Neutral
- The picker writes `displayMode` through the same partial PATCH as every other profile
  field, so it cannot clear a threshold on the way.
- `PlannedSessionPreview` keeps its own metric list; only the decision recorded in its
  comment changes.

## References
- `../SHARPIT/src/lib/preferences/display-mode.ts` — the density, its default and the load wording
- `../SHARPIT/src/components/display-mode/expert-only.tsx` — how the web hides an expert block
- ADR 0004 — semantic color and a tinted coach pill
- SHARPIT ADR-040 — native never calls `/api/presentation/*`

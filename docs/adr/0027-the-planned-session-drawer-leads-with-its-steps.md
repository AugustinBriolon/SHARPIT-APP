# 27. The planned-session drawer leads with its steps

Date: 2026-10-26

## Status

Accepted. Amends [ADR-0025](0025-a-planned-session-is-sent-to-the-watch-from-its-drawer.md): the watch entry leaves the « … » menu when it is the drawer's docked action.

## Context

The drawer (`PlannedSessionDrawer`, through `PlannedSessionSummary`, shared with the generator's « Séance proposée ») stacked six white panels of the same weight: figures, « Avant », « Déroulé », « Après », « Consigne », « Pourquoi cette séance ». Since SHARPIT ADR-114 added the routines, the steps — the session itself — came after a four-to-eight-line warm-up list. « Avant » sat above a first step named « Échauffement », so the session read as warming up twice. The coach's reason, what makes the session personal, was last. The time the athlete actually blocks (routines plus session) was shown nowhere, and the one action that readies an endurance session, sending it to the watch, sat in the « … » menu.

## Decision

We will give the drawer one leading panel, the steps', and put everything else around it:

- The header and the figures sit on the canvas, not in cards: an ink sport tile, the sport, « Clé » and the date, the title, then the figures split by hairlines.
- The coach's reason comes right under the figures, on the canvas under its eyebrow, three lines then tap for the rest. The coach pill (ADR-0004) follows it.
- A bar names the whole: « Au total ~57 min », split into Mobilité / Séance / Étirements in proportion (`SessionSequence`, absent without routines or a duration).
- The routines fold to one line each, « Mobilité avant » and « Étirements après » (renamed from « Avant » / « Après »), with their count and length; a tap opens the moves, each name on its own line with its dose and cue under it.
- The session's one readying action is docked at the bottom (`SharpitActionDock`): « Lancer la séance » for a strength session the phone can follow, else « Envoyer sur ma montre » (« Renvoyer », quieter, once sent). It is then left out of « … ».
- The bar title is empty until the header scrolls away, then shows the session's title.

## Options considered

### Option A — Keep the stacked panels, reorder them

Least change. Cons: six equal surfaces still give no hierarchy; the routines stay as long as the steps; the watch stays hidden.

### Option B — One leading panel, routines folded, action docked (chosen)

The steps are what the athlete follows, so they are the only open panel; the routines are a margin, counted in the total and one tap away. Cons: the moves are no longer readable without a tap; one more component state (folded / open) per routine.

### Option C — Tabs (Séance / Mobilité / Pourquoi)

Shortest page. Cons: hides the coach's reason and the routines behind controls nobody opens, and splits one object into three screens.

## Consequences

### Positive

- With the routines folded, the steps begin on the first screen of an iPhone mini, after the coach's reason.
- « Échauffement » names one thing only, the session's first step.
- The total time answers « can I fit this in? » without arithmetic.
- An endurance session reaches the watch in one tap from its drawer.

### Negative

- A routine's moves take a tap to read, and its folded state is not remembered between openings.
- The « … » menu no longer lists the watch when it is docked, so it differs between a session with Garmin linked and without.

### Neutral

- The generator's « Séance proposée » page gets the same layout, without the dock (it has no session to send yet).
- `SharpitIconTile` now resolves SharpIt's custom symbols as well as SF Symbols.
- Pinned by the `planned-session` light and dark snapshots.

## References

- SHARPIT-WEBAPP ADR-114 (session routines)
- [ADR-0004](0004-semantic-color-and-a-tinted-coach-pill.md), [ADR-0025](0025-a-planned-session-is-sent-to-the-watch-from-its-drawer.md), [ADR-0026](0026-let-the-layout-explain.md)

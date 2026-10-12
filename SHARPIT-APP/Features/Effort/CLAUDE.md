# Effort and Adaptation

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Effort and Adaptation.** The web's block-scale readings (`/plan/charge`, `/plan/adaptation`) live
under the week, as SHARPIT's IA orders My week — the plan, then the trajectory; overnight recovery
stays on Résumé. Plan's current week ends on « Trajectoire » (`PlanTrajectoryCards`: two tiles,
today's strain against its verdict and the adaptation index against its trend, worded by
`PlanTrajectoryTile`), read by `PlanView` from `/api/v1/effort` and `/api/v1/adaptation` on open and on
`calendarRevision`; a tile pushes `EffortView` or `AdaptationView` in Plan's stack. Both are day
drill-downs (`V1EffortResponse`, `V1AdaptationResponse`, data-days domains `effort` and `adaptation`),
their sections shared in `DayDetailSections` (`DayDetailAlert`, `DayDetailRationale`,
`DayDetailEvidenceSection`, `DayDetailDimensionRow`, `DayDetailConfidenceFooter`). Effort: the strain
on `SharpitHeroScore` out of 21 to the tenth (no dial — a radial gauge never dominates a hero), the
web's one line under it (fresh in N days, else days stacked, else the fatigue type), « Surmenage
fonctionnel », the verdict with the capacity and the reasons, the load as four tiles named for the
reading (`EffortReadout`: « Charge du jour / Charge 7 j / Montée / Forme » or « TSS du jour / TSS 7 j /
ACWR / TSB », the ramp's zone in the web's words), the day outside training (steps, stress, Body
Battery — no scale, none has a norm), the strain's composition, the five fatigue dimensions (higher
is worse, missing ones say so, the dominant one tagged), then in the expert reading only — the web's
`ExpertOnly` — the PMC curves (CTL, ATL dashed, TSB) and eight weeks of load against their average.
Adaptation: the index and its status, the trend, « Plateau » and « Surcharge sans gain », the verdict,
the brake's score and the next block's load (`AdaptationReadout.loadMultiplier`: « Neutre » within
±0,5 %, else « ×0,90 »), the dimensions with the brake first and tagged « Frein » (an unavailable
neuromuscular efficiency is left out and explained, as the web does), the evidence and the days of
history. The figures, tones and words are the server's; the readouts only say them.

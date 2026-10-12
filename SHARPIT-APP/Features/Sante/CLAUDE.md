# Santé

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Santé.** The athlete's health as a check-up (`SanteView`, SHARPIT ADR-053), ranked by what
matters most. It opens on `SanteHero`, on the page rather than in a card: the biological age in
`SharpitTypography.showcaseScore` on a halo in the reading's tone, a pill with the gap to the civil age,
and a ruler ten years either side of it — or, without the age (below Pro, missing data), how many
markers sit in their norm with one tick per marker in its tone — then up to three markers that moved.
Then: « À surveiller » (only when something deserves attention — resting HR up for days, HRV
under the athlete's range, short nights, a fast weight change), then « Zones sensibles »
(`SensitiveZonesCard`: what the open zones do to the plan, the question owed), which pushes their
own page (`SensitiveZonesView`, `SensitiveZonesStore`, `/api/v1/sensitive-zones`, SHARPIT ADR-068):
the open zones by the web's strategy (à protéger, en reprise, à corriger), then the resolved ones;
a zone (`SensitiveZoneDetailView`) shows what the plan does with it, the upcoming sessions that load
it, its 0–10 curve and timeline (readings and status changes, a relapse named), and moves it along —
« Faire le point » (`ZoneCheckinSheet`: severity, what the athlete could do, a word), edit and
declare (`SensitiveZoneFormSheet`, the body part picked from the web's list so the plan can check
it), under watch, resolved (proposed when two weeks of readings say 0/10, never automatic), « Ça
revient ». Every change goes out through `SharpitRetry` and reads the zones again: the strategy is
the web's. Then
« Signes vitaux » (resting HR, HRV, sleep, VO₂max), « Corps » (weight with its target, body fat,
visceral fat, muscle) and « Au quotidien » (steps, breathing during sleep). Everything comes from
`/api/v1/health/overview` (`SanteStore`, kept whole in the response cache so the page paints
offline): each marker read against a published norm, its source named, and against the athlete's
own month — the app computes none of it; `SanteReadout` only words it. A marker opens
`CorpsMetricDrawer` with its reading (`SanteReadingBlock`) when the web keeps its longer history
(`/api/v1/body/series`, through `CorpsStore`, which also still feeds the Poids widget), else its month
(`SanteMarkerSheet`). The drawer's curve follows the finger (`chartXSelection`: the nearest measure
and its date, a notch per measure) and draws itself left to right, its dots after, when a range
arrives. Free except the biological age, which is Pro (`SharpitProTeaser`); Pro without
the data it needs pushes `AccountView`. The weight target is set from the toolbar
(`WeightTargetSheet`), the sleep targets from Sommeil's (`SleepTargetsSheet`). Training thresholds are
not health: Paramètres › Entraînement › Seuils d'entraînement (`ThresholdsView`).

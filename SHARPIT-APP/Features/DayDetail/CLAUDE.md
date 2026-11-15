# Day drill-downs

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Day drill-downs.** Sleep and Recovery open from the Today gauges, Nutrition from Résumé's
nutrition ring and section (`ResumeNutritionSection`), Effort and Adaptation from Plan. All five are a
`DayResourceStore` inside `DayDetailScaffold`, which puts the day in the bar as a capsule
(`DayDetailDatePicker`: « Ven. 14 nov. », « Nuit du 13 nov. » for a night; it opens the month),
and keeps the tab bar, as every sub-page does; a new
day's drill-down is a v1 resource plus a sections view, not a new store. The store keeps every day it
read, and every day read anywhere this launch (`DayReadCache`, filled by `SharpitClient`'s day reads):
a day seen once opens at once, today included, and the server answers behind. A past day still fresh
is not asked for again; every write and pull-to-refresh make days stale, painted at once then read
again. It marks the
picker's history (`SharpitWeeks.history`, three years — Plan, Journal and the day screens share it) from `/api/v1/data-days` through `DataDaysMarker` (so a logged day is marked before it is
opened), and reads the six most recent days with data ahead of the athlete. A swipe on the content
turns the day (`DaySwipe`: right for the day before, left for the day after, never past today — the
days turn as pages: the day before and the day after are drawn right against the page (as read,
else in their loading shape; the store reads them ahead), the finger drags all three and a turn
brings the one beside into place — no fade, no gap; it resists where no day lies; a day picked in
the strip or the calendar nudges in from its side of time; the title's date and the day's words
and figures change in place — no roll, no fade, no sweep (`.transaction` drops the animation on
the content, the slide stays) — a day not read yet shows redacted in its shape; a swipe that
starts on a row or a button never opens it — the turn is an exclusive UIKit pan that fails on
vertical drags, so the scroll keeps those) and
the left edge stays « back » — these screens and Journal turn off iOS 26's pop-from-anywhere
(`interactiveContentPopGestureRecognizer`) while they show. Journal swipes its rows, not its
week strip, which pages weeks.

**Sommeil, Clinique.** The night follows its mock-up, on the sheet under the sleep wash: a status
pill from the adequacy (`SleepSheetReadout.status`), the duration, « Score 64 / 100 · 1 h 10 de moins
que ton besoin », then the night's course — one rounded block per stretch of a stage on four lanes
(awake, REM, light, deep) under its clocks (`SleepTimeline`, `SleepSheetReadout.axis`), or the
stages' shares as one bar when the watch kept no course — a line per stage (its mark, its share,
its length; « Éveils 3 fois »), and the last fourteen nights as bars against the need, the night
read in full colour. Below: what shaped the score, tonight's bedtime, the sleep bank, as sections.

**Récupération, Clinique.** The score in a ring, the state as the title, why in a sentence
(`RecoveryReadout.summary`); « Ce qui pèse » — a line per dimension with its place on a track, the
weakest tagged « Limite » (`RecoveryReadout.weights`); a bordered line that says how far the
reading can be trusted, with « En parler au coach ».

**Nutrition, Clinique.** What is left of the day's energy in a ring beside Objectif, Exercice and
Mangé; the three macros between hairlines, each on a thin bar in its hue; the coach's reading in a
bordered card; « Repas » as lines (name over foods, energy, « Ajouter » on an empty meal); an ink
« + » floats at the foot.

**Bar, second pass (the athlete's call, 2026-11-15).** Every day screen carries the same bar: the
way back, the day in its middle (`DayDetailDatePicker`, a chevron beside it, opens the month) and
the screen's own « ⋯ » at the right (Sommeil: its targets; Nutrition: add, scan, targets). No two
buttons share a glass capsule. Sommeil's foot is lines: « Ce soir » (bedtime, screens off, the
night's need and what raised it), the coach's insights, a bordered line to the coach, then « Banque
de sommeil » under « En dette » / « À l'équilibre » as a pill. A day with nothing eaten is the same
Nutrition page at zero (`NutritionReadout.emptyDay`, from the food log's targets), « Copier la
veille » under the meals — never a different screen.

Sommeil's one action, its targets, is a button in the bar — a menu only where a screen has several.
Nutrition floats its own « + » at the foot, over the tab bar.

**Sommeil without its course.** When the watch kept only the totals, the night is still four lanes
(`SleepSheetReadout.lanes`): each stage one block as long as its share, all starting at the left —
how much of each, never when. With the course (Apple Health's segments) the timeline draws as before.

**Tab bar everywhere (2026-11-15).** No sub-page hides the tab bar or swaps it for a floating home
button any more (`cliniqueReturnButton` is gone, the athlete's call): the bar's back is the way out.
Sommeil reads the night's course from Apple Health for the day on screen (`store.selectedDay`), and
never draws a night with another one's course; a night without a course keeps the four lanes, one
block per stage.

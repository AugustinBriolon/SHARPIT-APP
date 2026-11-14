# Day drill-downs

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Day drill-downs.** Sleep and Recovery open from the Today gauges, Nutrition from Résumé's
nutrition ring and section (`ResumeNutritionSection`), Effort and Adaptation from Plan. All five are a
`DayResourceStore` inside `DayDetailScaffold`, which puts the day in the bar as a capsule
(`DayDetailDatePicker`: « Ven. 14 nov. », « Nuit du 13 nov. » for a night; it opens the month),
hides the tab bar and floats a glass home button at the foot; a new
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

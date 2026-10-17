# Day drill-downs

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Day drill-downs.** Sleep and Recovery open from the Today gauges, Nutrition from Résumé's
nutrition card (`NutritionTodayCard`, below Régularité), Effort and Adaptation from Plan. All five are a
`DayResourceStore` inside `DayDetailScaffold`, which pins the day picker
(`DayDetailDatePicker`, built on the Plan's `SharpitWeekStrip`) above the content; a new
day's drill-down is a v1 resource plus a sections view, not a new store. The store keeps every day it
read, and every day read anywhere this launch (`DayReadCache`, filled by `SharpitClient`'s day reads):
a day seen once opens at once, today included, and the server answers behind. A past day still fresh
is not asked for again; every write and pull-to-refresh make days stale, painted at once then read
again. It marks the
picker's history (`SharpitWeeks.history`, three years — Plan, Journal and the day screens share it) from `/api/v1/data-days` through `DataDaysMarker` (so a logged day is marked before it is
opened), and reads the six most recent days with data ahead of the athlete. A swipe on the content
turns the day (`DaySwipe`: right for the day before, left for the day after, never past today — the
page follows the finger, resists where no day lies, and the new day slides in from its side; a day
picked in the strip or the calendar comes in from its side of time, the title's date rolls the same
way, a day not read yet shows redacted in its shape, Reduce Motion only fades; a swipe that
starts on a row or a button never opens it — the turn is an exclusive UIKit pan that fails on
vertical drags, so the scroll keeps those) and
the left edge stays « back » — these screens and Journal turn off iOS 26's pop-from-anywhere
(`interactiveContentPopGestureRecognizer`) while they show. Journal swipes its rows, not its
week strip, which pages weeks.

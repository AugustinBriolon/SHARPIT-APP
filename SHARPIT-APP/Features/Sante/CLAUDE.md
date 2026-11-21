# Santé

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Santé.** The athlete's health as a check-up (`SanteView`, SHARPIT ADR-053), ranked by what
matters most. It follows its mock-up (`docs/adr/0035`): « Santé » in the bar's row
with « Partager » and « + » (a blood test, the weight target). `SanteHero` is three rings between
hairlines — the biological age (a lock that opens the paywall below Pro), the markers in their
norm, the VO₂max. Only the middle ring is a share (N of M markers); the age and the VO₂max are
closed rings, since neither is a part of anything, and a line under each says how to read it
(« 3 ans de moins », the norm's words) — a half-filled ring at an age equal to the civil one read
as half done (the athlete's call, 2026-11-14). « Tendances » (`SanteTrends`) draws a marker's month as a line over its area, the last
reading in a bubble; its subtitle picks the marker, « Comparer » lays a second one over it, each
on its own span (`SanteTrendReadout.normalised`). Then the tables (`SanteTable`: Marqueur, Statut,
Valeur): « N biomarqueurs », the latest blood test, and « N repères », the measured markers —
« Bon » or « À surveiller » as a pill, none for a neutral tone or a result without an interval.
Then: « À surveiller » (only when something deserves attention — resting HR up for days, HRV
under the athlete's range, short nights, a fast weight change), then « Zones sensibles »
(`SensitiveZonesCard`: what the open zones do to the plan, the question owed), which pushes their
own page (`SensitiveZonesView`, `SensitiveZonesStore`, `/api/v1/sensitive-zones`, SHARPIT ADR-068):
the open zones by the web's strategy (à protéger, en reprise, à corriger), then the resolved ones, under the open zones marked on both faces of the body in their strategy's
tint (`SensitiveZonesBodyOverview`);
a zone (`SensitiveZoneDetailView`) shows what the plan does with it, the upcoming sessions that load
it, its 0–10 curve and timeline (readings and status changes, a relapse named), and moves it along —
« Faire le point » (`ZoneCheckinSheet`: severity, what the athlete could do, a word), edit and
declare (`SensitiveZoneFormSheet`, the body part touched on a silhouette, face or back — a man's or a woman's figure from the
profile's sex (`SensitiveZoneFigure`, the man's for anything else), every spot inside both (tested) —
`SensitiveZoneBodyPicker`, `SensitiveZoneBody`: every part of the web's list has its spot, a paired
part takes the side the finger landed on, both sides read « des deux côtés », the side question
only asked off the body; a part the server offers that the map does not draw stays a chip, « Autre… »
writes one — so the plan can check it), under watch, resolved (proposed when two weeks of readings say 0/10, never automatic), « Ça
revient ». Every change goes out through `SharpitRetry`. A status change (« Ça revient », resolve, monitor) shows on the tap and is put back with an inline error if the web refuses it; the other changes wait on their sheet, then read the zones again: the strategy is
the web's. Then
« Signes vitaux » (resting HR, HRV, sleep, VO₂max), « Corps » (weight with its target, body fat,
visceral fat, muscle) and « Au quotidien » (steps, breathing during sleep). Everything comes from
`/api/v1/health/overview` (`SanteStore`, kept whole in the response cache so the page paints
offline): each marker read against a published norm, its source named, and against the athlete's
own month — the app computes none of it; `SanteReadout` only words it. A row opens
`CorpsMetricDrawer` with its reading (`SanteReadingBlock`) when the web keeps its longer history
(`/api/v1/body/series`, through `CorpsStore`, which also still feeds the Poids widget), else its month
(`SanteMarkerSheet`). The drawer's curve follows the finger (`chartXSelection`: the nearest measure
and its date, a notch per measure) and draws itself left to right, its dots after, when a range
arrives. Free except the biological age, which is Pro (`SharpitProTeaser`); Pro without
the data it needs pushes `AccountView`. The weight target is set from the toolbar
(`WeightTargetSheet`), the sleep targets from Sommeil's (`SleepTargetsSheet`). Training thresholds are
not health: Paramètres › Entraînement › Seuils d'entraînement (`ThresholdsView`).

**Analyses de sang.** `BloodTestsCard` pushes `BloodTestImportView` (`Features/BloodTests`, SHARPIT
ADR-128, `docs/adr/0033`): pick the lab's PDF or scan the paper, read on the device
(`BloodReportReader`: text layer, else Vision; `BloodReportParser`: by position), correct every value
in `BloodTestReviewView`, then `POST /api/v1/blood-tests` with the results only. The document is
never copied or sent, and no test fixture holds a real report.
The card now pushes `BloodTestsView` (`BloodTestsStore`, `GET /api/v1/blood-tests`): the tests latest
first, then « Évolution », the markers measured in two tests or more (`BloodMarkerHistory`). A test
opens `BloodTestDetailView` (the clean table, delete from « … »), a marker `BloodMarkerHistoryView`
(its curve over the lab's latest interval, every value). « + » pushes the import, which closes on save.
`BloodMarkerReadout` words every result, in the review and the history alike.
Under the table, `BloodTestReadingCard` (`BloodTestReadingStore`, `GET /api/v1/blood-tests/{id}/reading`,
SHARPIT ADR-129) shows the sourced training reading — the server's findings, doctor-worthy ones
first — or `SharpitProTeaser` below Pro; it says nothing when the read fails, under real values.

**Suivi.** What is followed on its own page closes Santé as lines of one table (`SanteLinkRow`:
a name over what it holds, a status word when one is owed, an arrow): « Zones sensibles »,
« Analyses de sang », and the biological age's requirements when Pro cannot compute it yet. No card.

**Zones sensibles, Clinique.** The list follows its mock-up (`docs/adr/0035`): « Signaler une zone »
in the bar, the count under the title (`SensitiveZoneReadout.count`), « Question du jour » in a
bordered card (the zone that asks; « Faire le point » opens its check-in, since the server takes a
reading and not « mieux / pareil / pire »), « Ce que ça change à ton plan » (each open zone's strategy
detail behind a bar in its status tone), « Ouvertes » (the strategy as a pill, the last eight readings
as bars, « gêne 2 / 10 · en baisse » — the trend from the last two readings, `standing`), « Résolues »
(a check, « résolue en juin »), then the body overview. `SharpitScreenDemo zones` shows it.

**Corps, Clinique.** `CorpsMetricDrawer` is a titled sheet with its cross: when and from where the
marker was read, its figure with the note as a pill, the range, the curve on the sheet, then min, max
and the count as lines.

**Une analyse, Clinique.** `BloodTestDetailView` follows its mock-up (`docs/adr/0035`): how many
values deserve a look as a pill, « Analyse sanguine, 16 sept. 2026 », how many sit in the lab's range,
then the results in Santé's own table (`SanteTable`; a line opens the marker's history) and the
coach's reading. The bar keeps the deletion. The mock-up's « depuis mars » and « prochaine » figures
are not shown: the app holds neither a trend per test nor a next date.

**Faire le point, Clinique.** A zone's check-in rates on hairline tiles, the chosen one lined in ink
with the level's hue as a mark under the figure (`ZoneSeverityScale`, shared with the onboarding);
what the athlete could do is a list of hairline tiles; « Enregistrer » sits in the glass dock.

**Second pass (the athlete's call, 2026-11-15).** The bar holds « Partager » and the weight target
only (a blood test is added from « Analyses de sang »). The biomarkers table lists five results,
those outside the lab's range first (`SanteReadout.leading`), then « Voir les N biomarqueurs ». A
marker's line opens with its glyph. A marker's sheet reads its norm and its month as two lines
(`SanteReadingBlock`: the norm as a status pill, never coloured words). « Partager » opens
`SanteShareSheet`: ready-made cards (`SanteShareCard.available`: bilan, biological age, VO₂max,
markers — only what the overview holds), one a page, sent as an image (`ImageRenderer`, light), or
the figures as text. `WeightTargetSheet` is as tall as its content, full height once typing. Zones
sensibles no longer opens on « Ce que ça change à ton plan »: each open zone carries its own effect
in two lines, the rest on its page. `SharpitScreenDemo share` shows the cards.

**Third pass, on the mock-ups (2026-11-15).** A marker's sheet (`CorpsMetricDrawer`) follows
« Corps »: the month's move and the target under the figure (`CorpsFormat.summary`), the period as
a small tray (`CorpsRangePicker`), the curve in the sleep hue over its area with no axes
(`SharpitScrubChart(hue:)`, still read under the finger), its two dates and the target under it,
then lines — norm, month, min, max, count, source. « Ajouter une pesée » is not built: the app
writes no weight. Analyses de sang follows « A-Sang-Liste »: the disclaimer under the title,
« Évolution » as one marker's curve over its lab bounds with a chip per followed marker (the curve
opens its history), then « Analyses » with the count, a line per report. `SharpitScreenDemo corps`.

**Share cards, posters (2026-11-15).** Three cards at most — markers in their norm, biological
age, VO₂max — each an ink poster: the brand, the day, one ring in the pillar's hue with the figure
inside, its meaning under it (`SanteShareReadout.reading`); the summary adds resting heart rate,
HRV and VO₂max as three facts. Fixed colours, so the image is the same in light and dark.

**Faire le point, redone (2026-11-15).** `ZoneCheckinSheet` is a titled sheet with its cross: the
question as its title, the pain on one `CliniqueScale` track (0–10, its word beside), what the
athlete could do as checked lines, a word for the coach, « Enregistrer » docked. The onboarding keeps
`ZoneSeverityScale`.

**Order and colour (the athlete's call, 2026-11-16).** Under the hero: « Tendances », « Aujourd'hui »,
« À surveiller », then the markers. « Aujourd'hui » is a ring strip like the hero's (`SanteDayState.Tile`
carries its pillar, glyph and fraction; « Effort visé » closes once the band is reached, the day's
strain not being in the payload). « À surveiller » is one plate in the watch status' hue, a dot a line.

**Aujourd'hui as gauges, À surveiller as lines (the athlete's call, 2026-11-16, later that day).**
Rings under the hero's rings read as the same section twice, and the tinted plate as a warning box.
« Aujourd'hui » is three lines (`SanteTodayLine`): glyph in the pillar's hue, name, figure, then a
gauge with a tick where the athlete usually stands (`Tile.baseline`); « Effort visé » has no gauge,
its state is a status pill (`Tile.status`). « À surveiller » is lines on the sheet, each behind a bar
in the watch hue, as the weekly review's « À retenir ».

**« Aujourd'hui » paints with the page (the athlete's remark, 2026-11-21).** It used to come in after
the rest, once `/api/v1/today` answered, and push the tables down. `SanteStore` now opens on the day
Résumé kept (`DayReadCache.lastKnown`); with none, the section holds its place drawn redacted
(`SanteDayState.placeholder`) until the read answers, and goes only if it fails with nothing kept.
Figures change in place; the gauges alone move, filling from empty on appear and to each new reading
(`SanteGauge`, `SharpitMotion.gaugeFill`). Written without Xcode: not built or seen yet.

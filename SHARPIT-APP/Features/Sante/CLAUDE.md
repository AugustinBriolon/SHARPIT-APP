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

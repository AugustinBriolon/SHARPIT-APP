# Activité

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Strength sessions.** A strength activity lists its exercises in the order done
(`ActivityStrengthSection`): each block of sets as « 4 × 8 · 60 kg » (« 3 × 45 s » when timed, no
load when bodyweight) and the exercise's volume; `StrengthExerciseReadout` words it, tested.

**The expanded map, Clinique.** It follows its mock-up (`docs/adr/0035`): a cross closes it; one glass
capsule at the top right stacks the map's style, « 3D » / « 2D » and, only once the camera has left
the route (`RouteFraming`: part of it out of view, or under 35 % of the map), the recentre; MapKit's
compass and scale sit under it. A card floats at the foot (`ActivityMapCard`): the replay as an ink
disc (`RouteReplay`, twelve seconds, paused and resumed at will; `RouteReplayPath` cuts the line over
a faint copy of it, coloured stretches included), the session's name — it closes the map — over
« 12,4 km · 58 min · 68 m de dénivelé » (`ActivityMapReadout.figures`), and « Cardio / Allure / Uni »
(`RouteColouring`, only the signals the recording carries; « Vitesse » off a run). A coloured route
(`RouteIntensity`) is cut in five levels between the session's own 10th and 90th percentiles, so one
sprint does not flatten the rest, in the zones' scale (`SharpitZoneTone`, blue to red); the card then
names the signal and what the colours span (« 134 – 170 bpm », `rangeText`). The path and the samples
are both thinned evenly by the server from one recording, so a point takes the sample at the same
share of the session. It opens plain: a triathlon's legs keep their own colours. Not built: the
mock-up's tooltip under the finger (« km 6,2 · 4:11 /km · 162 bpm »). The map runs to the screen's
foot only while expanded; collapsed it keeps the height its route is framed for.
`SharpitScreenDemo map` shows it.

**History.** Activité reads the history a page at a time (`activityPage`, 60 sessions, the server's
`before` cursor) and the next page when the list's foot comes into view; a refresh asks the newest
page again and keeps the older ones read. It follows its mock-up: « Activité » in the bar's row with
search and « + »; the sports done as chips (`ActivityFilterChips`, the chosen one ink, period and
duration behind the last chip); up to three records between hairlines (`RecordsReadout.highlights`,
opens Records); then the weeks (`ActivityHistory.weeks`: « Cette semaine », « Semaine du 3
novembre », each with its count and time), a session a line — glyph, title, day and figures, and
how it went against the plan as a pill (`ActivityRowReadout.standing`, « Libre » off plan).

**A session.** Its head is centred: the verdict against the plan as a pill (opens the compliance),
« Sport · Title », the day and hour; the figures three to a row between hairlines
(`ActivityMetricGrid`); « Ta séance » as lines (effort and feeling, compliance); splits as a table
(`ActivitySplitsSection`); the coach's analysis as a section. The curves are one plot
(`ActivityChartsSection`): each chosen measure a line in its hue on its own scale
(`ActivityCurve.level`), opening on the effort and the heart rate; the legend toggles a measure
and, under the finger, reads its value; a table under the plot gives each one's average and best. The sheet's wash follows the verdict.

**History filters.** Activité filters what it has read in place (`ActivityFilter`): the search
field on the title and sport, and the bar's filter menu — a sport the athlete did (the most
frequent first) and a period; the list's foot keeps reading older pages, and an empty result offers
« Chercher plus loin » while more waits. Its glyph fills while a filter narrows the list; its pickers are inline, all at the menu's
first level, which draws in the app's `AccentColor` (ink, near-white in dark): a picker's own submenu
(`.pickerStyle(.menu)`) is drawn by UIKit in grey rows with tinted glyphs that no tint reaches;
a filter that empties it offers « Tout afficher ».

**Logging and editing a session.** Activité's « + » opens « Saisir une séance »
(`ActivityFormSheet`, `ActivityDraft`): sport, start, duration, the sport's measures (distance in
km, in metres for a swim; elevation; average heart rate), the strength exercises (the plan's own
`StrengthExercisesEditor`), effort, feeling and notes — `POST /api/v1/activities`, the web's
`createActivitySchema`. A done session's « … » (`ActivityActionsMenu`, among the page's floating
controls) edits it in the same sheet (PATCH, only what moved), links it to a goal and deletes it
after a confirmation.
Both forms wait for the server, whose figures the page shows; every change bumps
`ShellRouter.activitiesRevision` (and the calendar's), so the list and the plan read again. The
compliance sheet's « … » adds « Réanalyser » (`/api/v1/planned-sessions/[id]/analyze`): the
server answers at once and writes the reading behind, and the page looks for it a few times.
A session of the last week asks about each open pain or injury with no reading since it started
(`PainReassessment`, the web's `dueReassessments` « after_session » rule), worst first, each row
opening the zone's own `ZoneCheckinSheet`.

**Records.** A trophy at the bar's leading edge (no tile in the list) pushes `RecordsView` in Activité's stack — the web keeps records in
Progression › Performance, and the app has no Progression tab, so they sit with the sessions they
come from. `RecordsStore` (owned by `ActivityView`, created on the first open, so a reopen shows at
once and refreshes quietly; a failed refresh keeps what is shown) reads `/api/v1/records`
(`RecordsClient`, `V1Records`): per sport (Course / Vélo / Natation, a `SharpitSegmentedControl`) each
category of the web's `PR_DEFS` as a card — the #1 in `SharpitColor.recordAccent` with its meta, its
age in the web's words (`RecordsReadout.narrative`: « il y a 3 mois », « record de la saison ») and
« Nouveau » for two weeks, then #2–#5 — then for running the best time over each reference distance
(`runBests`, « Meilleurs temps »), and for cycling, in the expert reading only (`docs/adr/0006`, the
web's `ExpertOnly`), the power curve on Swift Charts (`PowerCurveCard`, categorical durations,
`chartXSelection` with a notch per duration). Every figure is the server's `displayValue`; a record
with an `activityId` pushes its session. Arrays decode through `LossyRecordArray`, so one malformed
record never blanks the page.

**Activity cache.** The list (`ActivityView`) is one scroll view for every phase, holding the
refresh control: swapping the scroll view with the phase left the control stuck pulled down. An activity's detail and streams are kept on disk as the raw JSON the server
answered (`ActivityDiskCache`, Application Support), because the in-memory cache died with each
screen's client and the heaviest read in the app reloaded on every open. `ActivityClient` reads
memory, then disk, then the network: a stream is kept for good once the server said it was
available (a recorded session's samples do not change), a detail for 12 h
(`ActivityCachePolicy`) and any age when the network fails. The app's own edits keep it true — a
generated narrative rewrites the detail, a subjective rating drops it. A planned session's breakdown, which Today's
payload does not carry, is kept there too: the drawer opens on the last one read and asks the
plan again behind it, since a plan is edited where a recorded session is not.

**Conformité, Clinique.** `ComplianceDetailSheet` opens on the session it was read against, the score
big (« 72 / 100 ») beside the verdict as a pill, the summary, then « Forces », « À travailler » and
« Ce que montrent les données » as titled sections of plain lines, and « Pour la suite » in a
bordered card. The mock-up's « Critère par critère » table (duration, intensity, structure, heart
rate, each with a status) is not built: the analysis carries sentences, not a score per criterion.
`SharpitScreenDemo compliance` shows it. Records, the technical analysis and the race analysis open
their sections on titles, without cards.

**Ressenti et analyse technique, Clinique.** « Comment s'est passée la séance ? »
(`SubjectiveEditorSheet`) rates on hairline tiles, the chosen one lined in ink (`RatingGrid`, shared
with the brick's evaluation) — no shadow, no coloured tick under a figure. The technical analysis
reads its figures plainly and each zone as a line: its name, its range over a gauge filled to its
share in the zone's hue, its time. `SharpitScreenDemo feeling` shows the sheet.

**Conformité, visible (2026-11-15).** The verdict pill in a session's head is no longer the way
in: under the figures a bordered card reads « Conformité au plan · 72 / 100 · Voir le détail » and
opens the compliance sheet. « Statut d'activité » is a titled sheet with its cross: the mode held,
until when as a pill, the modes as lines (a check on the one held), « Durée ».

**Back swipe.** The page follows the finger back, so a control the swipe started on used to fire
on the page returned to. `InteractivePopGestureEnabler` turns the page's touches off while either
pop gesture runs (`BackSwipeTouches`), which cancels the press; a swipe let go half-way gives them back.

# Activité

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Strength sessions.** A strength activity lists its exercises in the order done
(`ActivityStrengthSection`): each block of sets as « 4 × 8 · 60 kg » (« 3 × 45 s » when timed, no
load when bodyweight) and the exercise's volume; `StrengthExerciseReadout` words it, tested.

**Route intensity.** The expanded map's layers menu has « Heatmap »: it colours the route by heart rate (by speed
without it), in the training zones' family (`RouteIntensity`, `RouteIntensityTone`): five levels
between the session's own 10th and 90th percentiles, so one sprint does not flatten the rest. The
path and the samples are both thinned evenly by the server from one recording, so a point takes the
sample at the same share of the session — no server change. The recentre button shows only once
the camera has left the route (`RouteFraming`: part of it out of view, or under 35 % of the map).
Under the 2D/3D button (always shown: « 3D » on a flat map, « 2D » on a tilted one), a play button
redraws the route from start to finish over a faint copy of it, a dot at its head (`RouteReplay`,
twelve seconds, paused and resumed at will; `RouteReplayPath` cuts the line, heatmap stretches
included). The points are evenly spaced in time, so the line runs faster where the athlete did.

**History.** Activité reads the history a page at a time (`activityPage`, 60 sessions, the server's
`before` cursor) and the next page when the list's foot comes into view; a refresh asks the newest
page again and keeps the older ones read. It opens on « Cette semaine », the tab's one ink card
(sessions, time, distance, the days lit), then one card per month (`ActivityHistory`:
months keyed by year and month, each with its count and time), its sessions as rows split by
hairlines. Months are laid out lazily.

**History filters.** Activité filters what it has read in place (`ActivityFilter`): the search
field on the title and sport, and the bar's filter menu — a sport the athlete did (the most
frequent first) and a period; the list's foot keeps reading older pages, and an empty result offers
« Chercher plus loin » while more waits. Its glyph fills while a filter narrows the list; each filter is a submenu named with its current
value (Sport, Période, Durée), holding an inline picker, so every row draws in the app's
`AccentColor` (ink, near-white in dark): a picker's own submenu (`.pickerStyle(.menu)`) is drawn by
UIKit in grey rows with tinted glyphs that no tint reaches;
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

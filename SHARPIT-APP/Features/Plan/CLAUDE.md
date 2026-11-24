# Plan

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Plan generation and weekly review.** « Remplir ma semaine » is generated on the server in the
background (`/api/v1/coach/plan/jobs`, `PlanJobServing`): the app starts the job, follows its
drafts while in front, and picks it back up on its return (`PlanGenerationStore.resume`); the
server pushes « Ta semaine est prête » (`/plan/generator`, which opens Plan's generator through
`ShellRouter.isShowingPlanGenerator`), app open or not. The plan horizon (SHARPIT ADR-095) uses the
same job: when a running training plan is three days from its last planned session, the server
writes the next week itself, Résumé shows « Ta semaine est prête » (`PlanHorizonCard`, from
`/api/v1/today`'s `planHorizon`) and the generator picks it up as the latest job; untouched, the
server adds it the day before it starts. The weekly review ends with « Préparer ma semaine », which
closes the review and then opens the generator (one sheet at a time). The store is owned by `PlanView`. The
sessions appear one by one (`GeneratedWeekView`, shared with the onboarding's first week, which
still streams `/api/v1/coach/plan`). The server's Gate takes out what it rejects before the week
is shown, so « Ajouter » (`/api/v1/coach/plan/insert`) is never refused for safety.
While the coach writes, `GeneratingWeekView` names what it reads, one line after another
(`readingSteps`), then the sessions so far, with redacted rows still to come. A proposed session
opens on `ProposedSessionPage`, pushed inside the generator's sheet (HIG: one sheet at a time) and
a sheet only in the onboarding — the system's own transitions: a zoom from the row, tried, read as
the sheet vanishing. It shares `PlannedSessionSummary` with `PlannedSessionDrawer`, fed by
`PlannedSessionPreview(generated:)`: the steps (`breakdown`, resolved server-side like a planned
session's) and the coach's one-line rationale — no prose instruction, the coach writes none.
An endurance breakdown also carries `routines` (SHARPIT ADR-114, ADR-115): `PlannedSessionSummary` shows « Mobilité avant » above the steps and « Étirements ciblés » below, as `SessionRoutinePanel` lines folded by default (a tap opens the moves), tagged « Sur mesure » when the coach wrote them or « Facultatif » for the stretches, and « Au total » (`SessionSequenceBar`) adds them to the session's duration; a routine with no move (the stretches after a recovery session) shows no panel. The server resolves and doses them (library by intensity + declared zones, or the coach's); the strides before hard work are steps of the prescription, so they reach the watch. From the session's day on, where the plan can be written, the open panel asks « Fait / Raccourci / Sauté » (`PlanEditor.markRoutine`, PATCH `warmupStatus` / `cooldownStatus`), which the coach reads beside the session's first block. The summary's order (`docs/adr/0027`): header and figures on the canvas, the coach's reason, the screen's actions, the total, then the steps — the one open panel. `SharpitScreenDemo session` shows the drawer on `PlannedSessionPreview.demo`.
The row opens the session; its check is a button of its own.
A brick (legs sharing `brickGroupId`) is one entry in Plan (`PlanEntry.brick`, `PlanBrickCard`) and one
line in Résumé (`brickLegs`), and opens `BrickSessionDrawer`: the chain, the legs with their steps and the
transition between them; a leg pushes the single session's drawer (`isEmbedded`) for the watch and linking.
Done, it stays one entry (`PlanEntry.doneBrick`, `PlanDoneBrickCard`) when two legs or more were recorded
against it, and opens `DoneBrickDrawer`. One leg left is a plain session, as the web demotes it. A breakdown's repeated steps are gathered by their
server `group` (`PlannedStepSet`) under one « N fois » well — the block and its recovery, N times.
« Ajuster le planning » (`PlanAdapterSheet`, its `PlanAdjustmentStore` owned by `PlanView`) is laid
out as the generator — `CoachWorkingHeader`, `SharpitActionDock`, `SharpitPrimaryButton`, rows with
`SharpitSportBadge` and `SharpitKeepToggle` — and never shows the model's reasoning. The server
takes out the changes its Gate rejects; the ones kept go back whole (`V1AdaptChange.applyBody`) to
`/api/v1/coach/adapt/apply`, which stores them through the web adapter's own mapping, the coach's
steps included. A session (or a brick) missed in the last seven days carries « Rattraper ma
semaine » under its card in Plan (`PlanCatchUp`, read by the rows through the `planCatchUp`
environment action): it opens the adapter with the miss already said and starts it — one tap to
the coach's proposal for the rest of the week. Two or three sessions a week are key (SHARPIT
F2, `isKey`: a race, the hard sessions, the long outing, a brick — chosen by the web's rule, marked
on the proposal in `GeneratedWeekView` and stored on « Ajouter »): « Clé » (`SharpitInlineTag`,
shared with « Brick ») in Plan, Résumé, the proposal, and the session drawer's header — the coach
marks it; the athlete does not toggle it. The rest is optional: « Dommage pour hier » speaks
of a missed key session only, and a week with none marked counts every session as key.
« Bilan de la semaine » (Plan's « … ») is SharpIt Pro: `WeeklyReviewView` reads the latest review
from `/api/v1/coach/weekly-review`, writes the current week's on demand, and shows a
`SharpitProTeaser` on the server's 403. It is laid out like Health's summary: « Faits marquants »
(what went well, what to watch — split from the markdown's fixed headings by
`WeeklyReviewSections`), the week's figures as metric cards with quiet day bars and the average
dashed, next week, and the full text on its own page. `-SharpitWeeklyReviewDemo` shows it on a
fixed week in Debug builds.

**Trips in the week.** The coach's trips (Mémoire du coach, `/api/v1/coach-memory`, type `TRAVEL`) that fall in the week
shown are a stretch of the week's rail (the athlete's call, 2026-11-21, replacing the grey band of
2026-11-16, itself replacing the chip beside the status): the trip opens on a stop of its own above
its first day shown (`PlanTripStop`: its glyph on the rail, the place and the days over its name as a
day stands over its session, what training becomes as a pill, the sports when it narrows them), and
the rail runs in ink, 3 pt, down the days away (`PlanRail`), back to a hairline at home. A trip under
way before the week comes in from the top, one going on after it leaves by the last day
(`PlanTravel.overflow`). Nothing is filled: the sheet stays white, every row keeps its hairline.
`PlanTravel` compares calendar days — a trip's days are UTC
midnights on the server, the week's are local — and the label opens `PlanTripsView` as a sheet. Plan's « … » →
« Déplacements » opens the same list (trips and constraints, under way then ahead); injuries, preferences and notes
stay in the coach's memory. `CoachMemoryEntryForm` is pushed inside either list. `TripTraining` holds the choice:
the server derives the constraint from the sports as soon as any are sent (`resolveTrainingFields`), so « Allégé »
carries no sports, and the sentence under the choice says what will really happen. The server sends a trip's
days as `yyyy-MM-dd`; `CoachMemoryEntry` reads them as UTC midnights and refuses a day it cannot read (it once
fell back to today, showing every trip as starting today). Saving opens nothing: a trip the sessions ahead no
longer fit shows on Résumé (`TravelConflictCard`, `docs/adr/0029`), whose tap sets
`ShellRouter.pendingTravelConflict`; Plan then opens « Ajuster le planning » with the trip said
(`PlanTripAdaptation.focus(for:)`) through `startAdapter(focus:catchUp:)`, as « Rattraper ma semaine » does.

**Editing the plan by hand.** Plan's « + » opens « Nouvelle séance » (`PlannedSessionCreateSheet`);
a session's drawer carries « … » (`SessionActionsMenu`: Envoyer sur ma montre when it is not docked, Lier à une séance
réalisée, then Modifier, Déplacer to one of the next seven days, Supprimer after a confirmation —
each group only where the screen offers it, and no « … » when none is). « Modifier » is pushed inside the drawer, one sheet at a
time. `PlanEditor`, owned by `PlanView`, writes them: an edit, a move and a deletion show on the tap
(`PlanStore.show` / `showRemoved`) and go out behind through `SharpitRetry`; a creation waits for
the server's id. Every write bumps `calendarRevision`, and that reload is what puts a refused change
back. `PlannedSessionDraft` sends only what changed (`PlannedSessionFields`: an absent key leaves a
field, `null` clears it); the day goes as its local noon, as the web's form sends it. The server
checks the déroulé (or a strength session's exercises) on a creation or a change of sport only, so a
coach's session with structured steps and no prose stays editable; a change of sport clears those
steps. A strength exercise keeps the keys the form does not show (rest, the watch's exercise), and a
rename drops the two that name the old one. A brick is the coach's chain and is not edited by hand.
A done session's « Conformité au plan » sheet can delink the activity (`link` with
`activityId: null`): the session is to do again and its analysis is gone.

**Sending to the watch.** A run, ride or pool session not done carries « Envoyer sur ma montre » docked at the bottom of its
drawer (`docs/adr/0025`, `0027`; « Lancer la séance » takes the dock for a strength session the phone follows) when Garmin is linked — `PlanView` reads
`/api/v1/sync-status` with its extras. It posts `/api/v1/garmin/workouts/from-planned-session`
(`GarminWorkoutClient`); the server resolves the targets and schedules the workout on the session's
day. The entry reads the receipt the plan carries (`garminWorkoutId`, `garminWorkoutScheduledDate`,
kept through a local edit by `applying`): « Renvoyer sur ma montre » once sent (`WatchPushState`),
asked before replacing unless the day moved. Pro-only: a Free athlete's tap opens the paywall. A Garmin refusal is a 403 or
429 in the server's words, shown in the toast, never a sign-out.

**Guided strength session.** « Lancer la séance » closes the drawer and hands the session to
`GuidedWorkoutDock` (`RootView`'s, in the environment; `docs/adr/0030`): the same
`GuidedStrengthWorkoutView` is mounted over the tabs (`GuidedWorkoutDockHost`) and « Réduire la séance »
(a ⌄ at the top left, and on every pushed page; « Terminer la séance » and « Quitter » sit in the « … » at the right) only slides it away — sets, rest, clock and heart rate keep running — while the tab
bar's bottom accessory (« Push day · 12:34 », a glass capsule before iOS 26.1) brings it back. One
session at a time: a second launch reopens the running one. The summary offers « Reprendre la séance ».
A hold set has a ▶ that pushes `GuidedHoldPage` (`GuidedHoldClock`): « Mets-toi en place » (5 s), then
the hold, or for a `perSide` set « Côté gauche », « Change de côté » (5 s), « Côté droit » (one set covers
both sides), the whole sequence shown from the start and the next step always named; a sound on each
step and its last 3 s, VoiceOver told, screen kept awake; ticked at the end. Set lines say
« par côté » and never show a 0 kg load; the server shapes the sets (SHARPIT ADR-121: no load on
mobility, a one-rep stretch becomes a 30 s hold, `perSide` from the coach or the taxonomy).
`SharpitScreenDemo strength` shows it in a two-tab shell, dock included.

**Clinique.** Plan's week follows its mock-up (`docs/adr/0035`). Each week is a sheet: « Plan » as
the page's title with « Adapter » (the adapter, opened empty) in glass beside it, how the week
stands as a status pill (`PlanWeekReadout`: « Dans les clous », « 2 à rattraper », « Semaine
bouclée », « Semaine libre ») whose wash the sheet takes, then three rings — Séances, Volume,
Charge — each what was done over what the week holds (`PlanWeekTotals`, counted from the entries the
list shows; a done session counts for what was recorded). « Semaine du … » opens the calendar; a
swipe turns the week. The days run down a rail (`PlanTimeline`): a dot per line — filled for done,
amber for missed, a bold ring for today, hollow ahead, grey for rest — the day and sport above the
title, and at the end a status pill once behind, the length while ahead. The week strip and the
focus card are gone. `SharpitScreenDemo plan` shows the week on fixed prescriptions around today.

**Chrome, phase, countdown.** The bar is its buttons only — « … » (add a session first) and
« Adapter » — with no fill and no fade; « Plan » heads the week's page level with them and scrolls
away with it (the athlete's call, 2026-11-14). Under it, beside the status pill, the week's place in the plan (« Spécifique · sem. 3
sur 6 », `PlanPhaseReadout.line`, from the active plan's weeks) and, right of the week's name, the
days to the race (`PlanPhaseReadout.countdown`). A line reads « Lun. 10 » over « Natation · Technique
2 400 m ». The screen has one wash, under the bar too, following the week shown.

**Séance prévue, Clinique.** The drawer follows its mock-up (`docs/adr/0035`): « Clé » as a pill,
« Sport · Titre » (`PlannedSessionReadout.title`), the day, the figures centred between two hairlines,
then « Déroulé » as a table (`PlannedStepTable`: how long, what with its note, the target; a repeated
set named once — « 5 fois » — over its lines, held by a rule), the coach's reason and the instruction
after the steps. The actions sit in one glass bar: the one that readies the session in ink (watch or
« Lancer la séance »), « Déplacer » (the next seven days) where the plan can be written, and the coach's
bubble; « … » keeps edit, link and delete. The mock-up's intensity blocks are not drawn: a step carries
no zone. « Ajuster ton plan » (`PlanAdapterSheet`) is a titled sheet with its cross: each change a
bordered card — day, what it does as a pill, the session and why, « Appliquer ce changement » — and
« Appliquer les N changements » (`PlanAdapterReadout.apply`).

**Bilan, générateur, renfo, semaine vide — Clinique.** `WeeklyReviewView` follows its mock-up
(`docs/adr/0035`): how full the week was as a pill (`WeeklyReviewReadout.standing`), « Bilan du 3 au
9 novembre », sessions / volume / load between hairlines (`strip`), the time by sport as a table (the
payload has no planned time or reading per sport, so the columns are sessions and time), « À retenir »
as lines behind a bar in their tone, the figures as rows, « La semaine qui vient » in a bordered card,
« Préparer ma semaine » docked. The generator's proposal (`PlanGeneratorSheet`) opens on « Ta semaine
est prête », « Semaine du … » and its total (`GeneratedWeekReadout`), each session a line — day,
« Sport · Titre », length and load, « Clé », its check — and docks « Ajouter N séances » with
« Refaire » in glass; the mock-up's « jours disponibles » chips are not built (the request does not
take them). The guided strength session keeps its flow and takes the sheet: exercises and sets as
lines, « Exercice 1 sur 4 », a check per set. The set in hand (`GuidedStrengthSession.nextSet`: the
exercise's first neither done nor skipped, a hold aside) is the mock-up's ink-lined card — its
number, repetitions and load each stepped in place (`stepReps`, `stepWeight` by 2,5 kg, unset rather
than « 0 kg ») — with « Série terminée » docked at the foot; the other sets stay lines typed in
place. The rest keeps its own page and « Ça fait mal » is not built. A week read, not over and holding nothing shows
« Ta semaine est vide » with « Remplir ma semaine » and « Ajouter une séance à la main » instead of
empty rings. `SharpitScreenDemo generator` shows the proposal's lines.

**Plan macro, déplacements, Clinique.** The macro plan (`MacroPlanSheet`) follows its mock-up: how
long and when, the phases as a rail — each as wide as its weeks, in its hue (`MacroPlanReadout.hue`),
the current one ringed in ink — then « Les semaines » as one table (Monday, what the week works, its
load, this week in bold) and « Archiver ce plan macro » as an outline button. No card per phase, no
ink hero. Déplacements is a large-titled list with « Ajouter » in the bar. The mock-up's « Générer à
nouveau » dock and « Ce que ça change cette semaine » card are not built: the plan is archived then
generated again, and the trips carry no reading of their effect.

**Forme, Clinique.** The expert reading's « Forme » (`TrainingLoadCard`) is a section of Plan, not a
card: net form read big with « Dans ta zone » / « Hors zone » as a pill, chronic form and acute
fatigue as two figures, the six-week curves in blue and orange with net form dashed, « Charge par
semaine » as bars, the current week in ink. `SharpitScreenDemo forme` shows it. The mock-up's
acute / chronic ratio is not shown here: Effort already carries it.

**Second pass (the athlete's call, 2026-11-15).** Plan's « ⋯ » only acts on the week (add a
session, fill the week, talk to the coach); goals, macro plan, trips and the weekly review are
lines at the foot of every week (`PlanAroundSection`, « Autour du plan », each with what is known —
the phase, « 2 déclarés »). « Trajectoire » is two lines (`PlanTrajectoryCards`: name, reading as a
pill, figure, chevron). « Ajuster ton plan » and « Remplir ma semaine » open at part of the screen
while they only ask, and take all of it once the coach works. The macro plan says where the athlete
stands (« Semaine 3 sur 12 », the phase and what it is for, `MacroPlanReadout`), then each phase as
a line that opens onto its weeks — the current one open — each week's load a bar against the plan's
heaviest. Déplacements docks « Déclarer un déplacement »; a trip's line carries its glyph; the form
asks questions (« Où vas-tu ? », « Quand ? », « Tu t'entraînes ? ») and docks « Ajouter au plan ».

**Bar, two glyphs (2026-11-15).** Plan's bar holds « Remplir ma semaine » and « Adapter » as icons,
each its own glass button; the « ⋯ » is gone. « Ajouter une séance » opens « Autour du plan ».

**Déroulé, routines (2026-11-15).** A session opens at full height wherever it is tapped. The
déroulé keeps one width for the dose column and a slot for the exercise's picture on every line
(a glyph where none exists), so names and doses line up. « Consigne » is gone: the déroulé says
what to do. A routine is a hairline block with « Fait / Raccourci / Sauté » on the line itself
(where the session's day has come); a done session answers the same questions from its activity
(`ActivityRoutinesSection`, read from the linked plan session), so a forgotten mobility can still be said.

**Routines drawer (2026-11-15).** Mobility and stretches left the déroulé: the session's « ⋯ »
opens « Échauffement et étirements » (`SessionRoutinesSheet`): the whole in time, then each routine
laid open with its answer. Plan's « Autour du plan » no longer adds a session — that is done from
Activité.

**Guided session, exercises and history (2026-11-15).** The set in hand is validated in its own card
(« Valider la série »): a button docked at the foot sat under the tab bar, the view being mounted over
the tabs. The overview shows a mark per set and « En cours » / « Terminé » instead of « 2/4 séries »,
and no longer lists the exercises under the title. « Ajouter un exercice » (`ExercisePickerSheet`)
searches the athlete's own exercises first — each with « Dernière fois … · Meilleur … » — then the
bundled catalog; a name found in neither is created once its zone is named, kept as a note on its
sets (« Zone travaillée : … »: the server has no column for it), and found again once saved. It is
offered in a programmed session too: better noted than left out. `/api/v1/strength-exercises`
(`StrengthLibraryStore`, read once a launch and after a save) gives each exercise's last session and
best, computed from the logged sets; a set opens on the last load or hold only where the plan gives
none (`applyHistory`). The coach's generator reads these figures (SHARPIT `formatStrengthHistoryBlock`).

**Strength session into Apple Santé (2026-11-15).** A session followed on the phone and saved is
also written to Apple Santé as a traditional strength workout — its start, its end, its name, the
activity's id as external UUID (`HealthKitWriter.saveStrengthWorkout`), behind the save and never
blocking it. The right to write workouts is asked the first time. No energy is written: the app
measures none. Read back, SharpIt's own workouts are left out of the upload
(`StrengthWorkoutMirror.isOwn`), or the session would be logged twice. A session logged by hand is
not mirrored.

**Turning a week (2026-11-16).** « Plan » and the status pill are held still across a swipe and swap
at its middle; the rings stay in place too and dissolve over the first quarter of the turn. Both are
drawn outside their page meanwhile, so a week's `ScrollView` is not clipped (`scrollClipDisabled`) and
the header is framed to the page's width — the swap is measured against it. Checked on a screen
recording, frame by frame: clipped, the title vanished for the second half of every swipe.

**A set's line names both figures (2026-11-16).** « 15 × 10 kg » left the first figure unnamed: the
athlete typed a load there, it was stored as repetitions (25 reps at 10 kg for 10 at 25), and the
coach, who reads the last session, prescribed it back the next day. The line reads « 15 rép. × 10 kg ».
The history code was read end to end and swaps nothing.

**Exercise figures (2026-11-16).** An exercise's page shows « Dernière
fois », « Meilleur » and « Volume » as one strip of named columns between hairlines
(`ExerciseFiguresStrip`): the volume's column is there from the start, « — » until a set is done —
it used to appear with the first set and push the sets down.

**Standing exercise notes (2026-11-23, SHARPIT ADR-146).** Under an exercise's name its page shows
« Ma note » — the athlete's note that holds for every session of that exercise (a cue, a setting, a
pain to watch) — or « Ajouter une note »; either opens `ExerciseNoteSheet`, whose save waits for the
server (`PUT /api/v1/strength-exercises`, an empty note removes it). `StrengthLibraryStore` keeps the
notes by exercise key (`athleteNote(of:)`), a note written this launch on an exercise never logged
included. The picker shows it under the history line. The plan generator reads it beside the history.
A session's own set notes are unchanged.

**Exercise progression (2026-11-23).** An exercise already logged carries « Voir la progression »
under its figures, which pushes `ExerciseProgressionPage` (`Route.progression`): « 50 kg → 65 kg
depuis le 20 sept. », the best load of each day as a line (the longest hold for an exercise never
loaded; the Y axis does not start at zero), then every day's sets, newest first. Read from
`/api/v1/strength-exercises/progression?name=` (the last 60 days the exercise was done, folded name).
`SharpitScreenDemo exercise-progression` shows it on fixed days.

**A done session stands where it was done (2026-11-23).** A strength session planned for Monday and
launched on Sunday stayed on Monday, in Plan and in the calendar. The server's link now moves the
session to the activity's day and time (SHARPIT-WEBAPP `done-schedule.ts`; a brick's leg and the
same-day auto-link are left alone). The calendar copy (`AppleCalendarSync`) is kept right seven days
back as well (`PlanCalendarPlanner.lookbackDays`), a done session's event lasts what the activity
took, and an event is read as moved by the athlete only when it left the slot the app last wrote
(`writtenStartsKey`, `AppleCalendarPull.eventWasMoved`): before, any gap between plan and event sent
the session back to the event's slot, undoing a move made in the app.

**The exercise picker browses (the athlete's request, 2026-11-24).** With nothing typed,
`ExercisePickerSheet` lists « Tes exercices » (most recent first) then the whole catalog from A to Z
(`ExercisePickerReadout.browseSections`, a letter pinned over its exercises, « # » after Z), and
`ExerciseIndexBar` stands at the trailing edge — ★ for the athlete's own, then the letters: a tap or
a finger sliding on it jumps to the letter, a notch at each one crossed. The field is no longer
focused on arrival, so the list and the index are whole; typing searches as before. The catalog's
names are the dataset's — English for most, French only where an alias exists.

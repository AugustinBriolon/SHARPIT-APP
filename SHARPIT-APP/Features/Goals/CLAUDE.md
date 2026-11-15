# Objectifs

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Objectifs.** `GoalsView` is one list, no tabs: the next race on the ink plate
(`GoalOrdering.nextRace`: the nearest A race ahead, else the nearest race), the goals in progress,
then — further down, only when there are any — the goals reached. Its `GoalStore` is owned by
`PlanView`, so reopening Objectifs shows the goals at once and refreshes them quietly. A goal
(`GoalDetailView`) and a new goal (`GoalCreateView`) are pages pushed in the Objectifs stack, never a
sheet over the Objectifs sheet. A goal's « … » holds Modifier (`GoalEditView`, pushed, the same
fields as the creation) and Supprimer; the edit shows on the tap and sends only what changed
(`GoalDraft.changes(from:)`, a day as its local noon), so a race moved keeps the plan built toward it.

**Objectifs** gains, at its foot and only when there are any, « Réalisations récentes »: the last 15
`/api/v1/goals/achievements` (`V1GoalAchievement`, read by `GoalStore.load` beside the goals and again
after a goal is marked reached; a failed read keeps what was shown), each the goal, then
`GoalAchievementReadout.line` — the figure in the goal's unit (a chrono for `unit: chrono` or a
`performance` metric config), the period (« Semaine 27 · 2026 », « juillet 2026 », « Année 2026 »),
the day and « marqué manuellement » — as the web's `GoalAchievementsHistory`. One reached by a
session pushes it (`GoalRoute.activity`) in the Objectifs stack. A reached goal's single result (`_performance`) is left out
(`GoalOrdering.recentAchievements`): its « Atteints » card already reads it.

**A race run.** The server reads where each race stands (`status`: upcoming / raceDay / done /
awaitingResult, and `result`: the linked session and its time, from `raceGoalStanding`) and marks a
race reached when a session is linked once its day has come; unlinking never un-reaches it. A done
race sits under « Atteints » and reads « Terminée · 5:40:03 · −19:57 vs objectif »; its page swaps
the projection for « Résultat » (« Prévu 6:05 · Réalisé 5:40 ») and drops the projected split. A race
past its day with neither shows `RaceAwaitingResultNotice` atop Objectifs and on its page: « Lier ma
séance » (that day's sessions, longest first) or « Valider l'objectif ». The session's race header
offers « Valider l'objectif » while the race is not reached, « Objectif atteint » once it is.

**The projection is the server's.** `V1Goal.projection` (`V1RaceProjection`, decoded leniently) is the
only race projection; the app computes none. `RaceProjectionReadout` reads it for « Position »: the
race-day finish and range (« 5h41 », « 5h35 – 5h48 »), the gap from `deltaSec`, « Si c'était
aujourd'hui », the weekly trajectory (`RaceTrajectoryChart`, faster upward, target as a rule, hidden
below two points) with « −22 min en 8 semaines », « Régularité : 82 % des séances faites · fiabilité
moyenne », the server's `missing` hints with « Compléter mes seuils » (`GoalRoute.thresholds`), and
each projected leg with its source. No projection reads « Projection indisponible pour ce format ».
A done race's « Prévu » is the frozen pre-race projection, « Prévu (recalculé) » when not frozen.

**Clinique.** Objectifs follows its mock-up (`docs/adr/0035`): « Nouvel objectif » in the bar, the
race ahead opening the page — « Prochaine course · dans 37 jours » (`GoalsReadout.lead`), its name and
day, the server's projected finish against the aim, the legs as one bar in the data hues with their
times, the projection's reliability as a pill — then « En cours » (a ring, the goal, its month),
« Atteints » and « Réalisations récentes » as lines. No ink plate. `SharpitScreenDemo goals` shows it.

The race header sets the server's compact times with their spaces (« 2 h 28 », « 27 min »,
`GoalsReadout.spaced`); the goal's own page keeps the server's form.

**Détail d'un objectif, Clinique.** `GoalDetailView` takes the coach wash and drops its bar title:
the race's phase and role, its name, its day with the countdown on one line (no hero figure), then
« Position » — the projected finish read big with its range, the gap to the aim as a status pill, the
trajectory — and « Détail par segment » as lines marked in each leg's hue, a transition quiet between
them. Sessions and time are two plain figures; « Valider l'objectif » is the app's ink capsule.
`SharpitScreenDemo goal` shows it.

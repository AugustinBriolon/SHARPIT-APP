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
session pushes it (`GoalRoute.activity`) in the Objectifs stack.

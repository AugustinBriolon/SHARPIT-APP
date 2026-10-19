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
shown carry a chip after the week's dates (`PlanTravelChip`, the web's `TravelContextBanner`: the
first trip's name, « +1 » for more); `PlanTravel` compares calendar days — a trip's days are UTC
midnights on the server, the week's are local — and the chip opens the coach's memory as a sheet.

**Editing the plan by hand.** Plan's « + » opens « Nouvelle séance » (`PlannedSessionCreateSheet`);
a session's drawer carries « … » (`SessionActionsMenu`: Modifier, Déplacer to one of the next seven
days, Supprimer after a confirmation). « Modifier » is pushed inside the drawer, one sheet at a
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

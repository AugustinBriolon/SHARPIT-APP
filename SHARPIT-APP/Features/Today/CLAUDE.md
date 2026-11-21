# Résumé (Today)

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Morning proposal.** As soon as the night is read, the web's morning recalibration may propose
today's session eased or raised (`/api/v1/today`'s `morningProposal`), shown under the verdict
(`MorningProposalCard`: the change in one line, why in one sentence, the plan beside the proposal
under « Voir le détail »; one primary button, « Garder le plan » as plain text). Until the check-in is
done (`checkInDone: false`) the card says it was read from the night alone and opens the check-in
from Résumé; once the check-in reached the server (`MorningWellnessStore`'s `onSaved` bumps
`ShellRouter.checkInRevision`, Résumé reads the day again) the server replaces a proposal still
waiting with one read with it.
« Alléger » / « Augmenter » or « Garder le plan » answers `/api/v1/morning-recalibration/action`
(`TodayStore.respondToMorningProposal`): the card leaves on the tap, comes back with the server's
reason if refused, and an accepted proposal reloads Résumé and bumps `calendarRevision`.

**Trip conflict.** `/api/v1/today`'s `travelConflict` (today only, SHARPIT ADR-120) names the first
trip or constraint of the next 14 days whose sessions to do do not fit it — a pause, a sport off its
list, or a key or hard session under « Allégé ». `TravelConflictCard` shows it under `PlanHorizonCard`
(« Ton déplacement à Lyon bouscule ton plan », « 2 séances ne collent pas, du … ») and opens Plan's
adapter with the trip said (`ShellRouter.openTravelConflict`, `docs/adr/0029`). The server reads it
again on every load, so the card leaves once the sessions fit; it has no « Ignorer ».

**Activity status.** The mode chip in Today's toolbar writes `/api/activity-status` on every
pick — no explicit save, as on the web. A deadline that has passed is resolved back to
`active` server-side on read, so the app never expires one itself. Trips are not modelled:
the app carries `travelId` back unchanged rather than inventing one.

**Another day.** The date heads the page as a button (`dayTitle`, above the chips; pinned over the
loading, empty and failed states so another day is always one tap away): it opens
`SharpitCalendarSheet` (no future day, its « Aujourd'hui » to come back; each past day marked as on
the day screens — filled for a night or a session, muted for none: `DataDaysMarker` over the
`sleep` and `effort` data-days, `SharpitCalendarMark.dataMarks`). A swipe turns the day as on the
day screens (`daySwipe`: the days beside are drawn against the page — `TodayStore.knownFold`, read
ahead after each load — right for the day before, left for the day after, never past today; a swipe
that starts on a card never opens it). A day not read yet shows its loading shape under its date. Not a toolbar `.largeTitle` item: on iOS 26 that one takes no
touch. `TodayStore.select(day:)` names the page at once; the new day arrives from
(`/api/v1/today?trainingDayId=`, snapshot cached per day; any day read this launch,
today included, opens at once from `DayReadCache` while the server answers behind, and a past day is
not asked for again until a write or a pull-to-refresh); `selectedDayId` nil
follows today, midnight included. The page returns to the top when the day changes (`.id` on the fold), the loading shape keeps the chips row, and Sommeil, Récupération, Nutrition and Régularité (`ShellRouter.openPlan(on:)`, read by Plan as `planFocusDay`) open on the day shown. A past day is read-only: no ressenti, no check-in invitation, and it never
reaches the widgets. The ressenti opens on its own only from 6 h, once last night's sleep is in
or from 10 h (`RessentiPromptTiming`).

**Ressenti du jour.** The half-sheet (`RessentiDuJourSheet`) asks one thing: five named steps
(`RessentiStepPicker`, « Très mal » … « Très bien », the chosen one lime, no hue per step). Energy,
body, stress and a note for the coach wait under « Ajouter un détail », in the same picker with their
own words (`WellnessDimension.label`). The button says « Choisis ton ressenti » until there is an
answer; « Plus tard » is the bar's cancel action.

**Clinique.** Résumé follows its mock-up (`docs/adr/0035`). The date and its chips sit on the
backdrop (`CliniqueBackdrop`, ink on light), in the dark colour scheme; the day rises over it as a
sheet with rounded top corners (`cliniqueRisingSheet`), its wash following the verdict
(`VerdictReadout`). Down the sheet: `VerdictHero` (status pill, decision, the facts as one line),
`ResumeScoreRow` — one ring per overnight gauge, Nutrition (calories over the day's goal, from the
food log) and Régularité (sessions done over the week's, counted as Plan does with
`PlanWeekTotals`; the active days until that is read) — then « Séance du jour » as rows
(`SessionPlate`: glyph, title, one line of sport and figures, a status or an arrow), the morning
proposal, and the cards that ask for an answer (plan horizon, trip conflict). A ring opens Sommeil,
Récupération, Nutrition or Plan. Under a hairline each: `ResumeNutritionSection` (the day's energy
over its goal, three macro bars in the nutrition hue; opens the food log) and `TodayTimelineStrip`
(« Fil de la journée » as a rail of moments), read straight on the sheet, never as cards.
Régularité's column is always in the row, an empty ring until the week is read, and the loading
shape draws the same columns (`SharpitLoadingInstrument(showsNutrition:)`): the row never grows a
ring after it is drawn.
The date and its chips stay pinned while the page scrolls (`visualEffect` cancels the scroll's
offset) and the sheet, at least a viewport tall, passes over them. `SharpitLoadingInstrument` is the same shape with empty rings.

**States, Clinique.** While the day is read the verdict's place says so — « Lecture de ta nuit »
with its spinner over three quiet bars (`SharpitLoadingInstrument`), never a greyed fake verdict. A
day the server has nothing for (`TodayEmptyView`) rises as a sheet too: why, the scores as empty
rings, and « Connecte ta montre » (Paramètres › Connexions) beside the way to the web. A failed read
is the shared `SharpitStateMessage` on the sheet. The race card (`RaceDayCard`) is a bordered card:
the moment as a pill, the race, its format and aim or its result with the legs, the coach's word — the
mock-up's pace per leg and pre-start checklist are not in `/api/v1/today`. A done brick
(`DoneBrickDrawer`) opens on how far it is as a pill, the chain, its total and the legs as one bar,
then each leg and each transition as a line.

**The rail reads the clock (SHARPIT ADR-138, the athlete's remarks, 2026-11-21).** The server places
each beat of « Fil de la journée »: a meal at its foods' time (ADR-137), the coffee when it was noted,
a session at its activity's start or else its plan's. Only a session done fills its dot
(`V1DayTimelineEvent.isDoneSession`: the server's `state`, else « Faite » in the detail); a planned
one stays hollow — a green dot before the session read as done.

# Résumé (Today)

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Morning proposal.** As soon as the night is read, the web's morning recalibration may propose
today's session eased or raised (`/api/v1/today`'s `morningProposal`), shown under the verdict
(`MorningProposalCard`: what changes, why, the plan beside the proposal). Until the check-in is
done (`checkInDone: false`) the card says it was read from the night alone and opens the check-in
from Résumé; once the check-in reached the server (`MorningWellnessStore`'s `onSaved` bumps
`ShellRouter.checkInRevision`, Résumé reads the day again) the server replaces a proposal still
waiting with one read with it.
« Alléger » / « Augmenter » or « Garder le plan » answers `/api/v1/morning-recalibration/action`
(`TodayStore.respondToMorningProposal`): the card leaves on the tap, comes back with the server's
reason if refused, and an accepted proposal reloads Résumé and bumps `calendarRevision`.

**Activity status.** The mode chip in Today's toolbar writes `/api/activity-status` on every
pick — no explicit save, as on the web. A deadline that has passed is resolved back to
`active` server-side on read, so the app never expires one itself. Trips are not modelled:
the app carries `travelId` back unchanged rather than inventing one.

**Another day.** The date heads the page as a button (`dayTitle`, above the chips): it opens
`SharpitCalendarSheet` (no future day, its « Aujourd'hui » to come back; each past day marked as on
the day screens — filled for a night or a session, muted for none: `DataDaysMarker` over the
`sleep` and `effort` data-days, `SharpitCalendarMark.dataMarks`), and a past day shows an
« Aujourd'hui » pill beside it. Not a toolbar `.largeTitle` item: on iOS 26 that one takes no touch. `TodayStore.select(day:)` reads that day
(`/api/v1/today?trainingDayId=`), its snapshot cached per day; `selectedDayId` nil follows today,
midnight included. A past day is read-only: no ressenti, no check-in invitation, and it never
reaches the widgets. The ressenti opens on its own only from 6 h, once last night's sleep is in
or from 10 h (`RessentiPromptTiming`).

**Ressenti du jour.** The half-sheet (`RessentiDuJourSheet`) asks one thing: five named steps
(`RessentiStepPicker`, « Très mal » … « Très bien », the chosen one lime, no hue per step). Energy,
body, stress and a note for the coach wait under « Ajouter un détail », in the same picker with their
own words (`WellnessDimension.label`). The button says « Choisis ton ressenti » until there is an
answer; « Plus tard » is the bar's cancel action.

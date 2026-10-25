# Onboarding

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Onboarding.** A new account answers the first-login wizard before it sees the tabs: Toi (first
name, sex, height, birth date) → Ce que tu viens chercher → Sports → Matériel → Ta semaine → Objectif → Blessures →
Confidentialité (only when owed) → Sources → Première semaine (`OnboardingStep`). The server
decides who owes it (`onboardingCompletedAt` present and `null` on `/api/v1/athlete-profile`); the
phone only remembers a "done" per Clerk user, so a finished athlete never waits on a profile read.
The gate's read is retried, a refusal included (right after sign-up Clerk can hand out no token
yet); if it still fails, a finished athlete is let in offline, a new one sees « Réessayer »
(`AccountGateModel.Status.unreachable`) — let in, nothing would ever reopen the wizard.
« Ce que tu viens chercher » (`OnboardingMotivation`) shows the coaching as always in (locked: the
plan and its generation are never switched off) and four rows ticked by their fill — santé, habitudes
(journal), nutrition, régularité — none ticked to start with; leaving it writes all four `featurePrefs`
at once (`AthleteProfilePatch.setFeatures`), so what stays unticked is out of the app from the first
tab, back through Paramètres › Pages et widgets. Sports accepts an endurance sport or strength alone (SHARPIT ADR-086,
`PracticedSportCatalog.isPlannable`); a strength-only athlete gets a palier goal only and no
Seuils row in Paramètres. `AccountGateModel` owns the
`OnboardingStore`, so a session refresh that resolves the gate again never rebuilds the wizard, and
`OnboardingStepMemory` reopens the step reached after a quit. Each step is written as the athlete
leaves it: the first name on the Clerk user, the body, practiced sports, equipment,
`trainingAvailability`, a first goal through `/api/v1/goals` (its place picked from MapKit
suggestions, `OnboardingPlaceField`; a triathlete picks the distance — Sprint, M, 70.3, Ironman,
`OnboardingTriathlonFormat`, worded as the web's triathlon predictor reads it — and any race may
name its aim), the injuries as physical notes (`/api/v1/physical-notes`, which
the coach reads as sensitive zones) and the consents. Injuries are health data: while the consents
are owed they wait on the phone and are written with the privacy step, before the week is planned.
A tap carries the step it was made on, so one delivered again after the page moved is dropped
instead of skipping a step. Once the consents allow AI, the store asks `/api/v1/coach/plan` for the
next seven days — towards the goal just created — while the athlete links their sources; « Ajouter
à mon plan » sends the week back whole to `/api/v1/coach/plan/insert`, which stores it through the
web generator's own mapping (the coach's strength and endurance prescriptions included) or refuses
it before writing anything; Plan's generator uses the same route. The generated week is kept
while the answers the coach reads (identity, sports, equipment, availability, goal, injuries, AI
consent — `PlanInputs`) stay the same: `startFirstWeek` called again does not ask twice, and a
changed answer drops the week and writes it again. Then `/api/v1/onboarding/complete`
finishes the wizard. Without AI consent the step says so and finishes without a week. Sources switches
Apple Health on — a switch per Clerk account (`AppleHealthSource.bind(userId:)`), so a new account
on the same iPhone starts off — and links Strava, Garmin, Withings and the calendars through the same OAuth
hand-off as Settings › Sources, but offers nothing for MyFitnessPal, which the app never links
(`docs/adr/0013`, `docs/adr/0010`). Debug builds open the wizard on in-memory
services with the `-SharpitOnboardingDemo` launch argument (`OnboardingDemoHost`).

The page is one page: the header's tick dial (`SharpitTickGauge`, animatable, so it sweeps from step
to step) and the step's title stay put, and only the content under them slides in from the side the
athlete is heading. The dial's thumb shows from the first step, at its start, with the position
(« 1 / 10 ») inside the arc. A choice is seen by its fill — no haptic, no symbol
animates (a wiggle on every tile read as unfinished); triathlon is the app's own symbol
(`triathlon.circles` in the asset catalog), SF Symbols drawing none. Toi uses the design system's
inputs: `SharpitFormField` (the label above a soft well, a ring while focused — no card),
`SharpitSegmentedChoice` for the sex, `SharpitRulerPicker` for the height (a tape measure settling
on each centimetre, firmer on the tens — `SharpitHaptics`, Core Haptics, prepared as the finger
lands — nil until moved) and `SharpitDateField` (the age beside it, the wheel in a
short sheet: opened in place it grew the page into a scroll).

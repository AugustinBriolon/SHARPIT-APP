# Paramètres

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Pages et widgets.** Paramètres › Pages et widgets (`FeaturesView`) turns a part of SharpIt off —
Journal, Nutrition, Santé, Régularité (`SharpitFeature`). Each row says « Affiché » or « Masqué » and opens
its own page (`FeatureDetailView`): what it looks like (`FeatureShowcase`, the app's own components on example
figures, so the picture never drifts from the screen), the switch, why follow it and where it shows. Off, it disappears everywhere it shows: the
Résumé chip or card, the page, the Santé tab, the home-screen widget (a placed widget says it is
hidden, `WidgetFeatureOff`); its data is kept. `FeatureStore` in the environment (`\.features`)
holds the choice, saved to the account (`featurePrefs` on the profile, merged server-side like
`notificationPrefs`), applied at once and put back if the save fails; the last choice is kept in the
widget snapshot so the app opens with the right tabs.

**Paramètres.** A page of cards: the account and tier, the SharpIt Pro plate, then the one setting
answered in place — Apparence (`AppearancePreference`, per iPhone, applied to every window's
`overrideUserInterfaceStyle` so open sheets switch at once) — then Notifications, a page
(`NotificationPrefsView`: the switch, `PushNotificationManager.setEnabled`, where off unregisters
the device server-side since iOS owns the permission, then each kind in `notificationPrefs`; session reminders are local — `SessionReminderScheduler`
reschedules them from the plan on launch, on each return, on `calendarRevision` and on the switch,
an hour before a session's `startTime` or at 7:30 that day, by `SessionReminderPlanner`'s rules; every
tapped notification goes through `PushNotificationManager.destination(for:)` to
`ShellRouter.open(_:)` — `/plan/generator`, `/plan/review`, `/settings/sources`, `/activity/<id>`
for « Séance dans la boîte » (a synced activity counted for the plan: its share of the planned time
and the next session, `sessionDone`), `/plan/catch-up` for « Dommage pour hier » (yesterday's session
missed, `missedSession`: `ShellRouter.pendingCatchUp` opens Plan's adapter with the miss said, as
« Rattraper ma semaine » does), a tab), Sources de
données, Sports & équipement (the onboarding's own `SportChoiceGroups` and `EquipmentBySport`, saved as they change; the sports wait while no endurance sport is picked), Densité de lecture (its own page: the choice needs its
explanation), Donner un avis (`FeedbackView`: a note to the team, shown as sent on the tap and
posted behind to `/api/v1/feedback` with the app's version — the external beta's voice,
`docs/beta-testflight.md`) and Confidentialité, each row saying its state before it is opened. A page's explanation is the footer of its
list (`SharpitListFooter`), never a paragraph above it. Compte edits in
place: first and last name through Clerk's `user.update`, sex, height and birth date through
`AthleteProfilePatch`; e-mail, password and photo stay in Clerk's own sheet.

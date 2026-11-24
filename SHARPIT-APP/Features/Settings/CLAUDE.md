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

**Paramètres.** The grouped list, as every settings page (`docs/adr/0008`), in the brand's dress:
each row's label is `SharpitSettingsLabel` (the ink tile with its lime glyph, the title, what it holds
now), switches are lime (`SharpitSwitchStyle`, set once for the app). The account and tier first,
SharpIt Pro on the page's one ink row, then the one setting
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
données, Matériel (one page: the sports, then the onboarding's own `EquipmentBySport` lines, saved as they change; the sports wait while no endurance sport is picked), Densité de lecture (its own page: two cards side by side, as iOS shows Clair and Sombre, each
drawing the same example session in its reading through `ActivityFormat.trainingLoad`, its audience
in one line under it; then exactly what Expert adds, screen by screen), Donner un avis (`FeedbackView`: a note to the team, shown as sent on the tap and
posted behind to `/api/v1/feedback` with the app's version — the external beta's voice,
`docs/beta-testflight.md`) and Confidentialité, each row saying its state before it is opened. A page's explanation is the footer of its
list (`SharpitListFooter`), never a paragraph above it. Compte opens on its face
(`AccountHeader`: the photo, camera badge opening Clerk's sheet, the name as typed, the e-mail, the
tier — said once, so no row below repeats them), then « Connexion » (« Photo et sécurité », Clerk's
sheet; « Abonnement » to Pro, with its renewal or « Découvrir SharpIt Pro »), and edits in place:
first and last name through Clerk's `user.update`, sex, height and birth date through
`AthleteProfilePatch`, the age read under the birth date (`AccountAge.label`), not on a row of its own. Signing out asks first (`AccountView.signOut`, the same local wipe
as account delete) — the page's one confirmation, since it is the one thing that erases.

**Clinique.** Paramètres follows its mock-up (`docs/adr/0035`): a row is its title and, at the
trailing edge, what it holds (`SharpitSettingsLabel`, no glyph tile — on every settings page); the
tier is a pill in the bar; the groups are the mock-up's — you (« Ton profil » with age and height,
`SettingsReadout.profile`; « Seuils et repères »; « Matériel »; « Objectifs », which closes the sheet
and opens them in Plan), the coach (« Mémoire du coach »), the app (« Connexions », pages, notifications,
« Affichage » answered in place by a menu, density, language), then SharpIt Pro and help. The coach's
usage stays in Coach: Paramètres does not hold its quota. `SharpitScreenDemo settings` shows it.
Connexions (`ConnectionsView`) lists every source on one table: « Connecté » or « À vérifier » as a
pill on a linked one (the line opens its sheet), « Connecter » on the others — no « + » sheet — and
« Synchroniser » in the bar; `SharpitScreenDemo connections`.

**Sous-pages, Clinique.** Notifications, Pages et widgets, Confidentialité, Priorités, Langue,
Densité and Retour are large-titled sheets of lines (`sharpitGroupedList`), a section opening on
its title; switches are the brand's lime, darkened as the mock-ups draw it (`SharpitSwitchStyle`).
`SharpitScreenDemo notifications` / `account` show two of them. Rows keep their glyph tiles, which
the mock-ups do not draw.

**Second pass (2026-11-15).** The tier in the bar is a status, not a button (`SharpitBarBadge`: no
glass capsule on iOS 26). Priorités gives each source one control, its switch; which one leads is
its own line (« Source principale », a menu) shown once two are on, the leading source tagged
« Principale ».

**Utilisation du coach.** Under « Mémoire du coach », as the mock-up: the share of the budget spent
over a thin bar in the coach's hue, opening `CoachUsageSheet`. It reads « 38 % sur 24 h », not the
mock-up's « ce mois »: the budget is a rolling day (SHARPIT ADR-077). Hidden until the quota is read.

**Ton profil and Objectifs, in Paramètres (the athlete's call, 2026-11-25).** This replaces what is
said above about Compte's face and about « Objectifs » closing the sheet. The page is named as its
row, « Ton profil », on the large title every settings page takes, and is made of the same rows:
who is signed in on one line (`AccountLine`: the face, the name over the e-mail, a chevron — it
opens Clerk's sheet), « Abonnement », then « Identité » and « Profil », each row a glyph in the
settings column and its value typed or picked at the trailing edge (`AccountFieldRow`,
`AccountRowTitle`), and « Se déconnecter » as a row. No centred face, no tier pill (the bar of
Paramètres says it), no redaction: the rows stand and wait for the profile to be edited. « Objectifs »
is a page of the stack (`SettingsRoute.goals`, `GoalsView` on a `GoalStore` Paramètres owns); the
stack's path is a `NavigationPath` so a goal can be pushed from it. Plan still opens the same page
as a sheet.

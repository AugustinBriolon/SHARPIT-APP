# Widgets

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Widgets.** `SharpItWidgets` is a WidgetKit extension (« Séance du jour », « Verdict du jour »,
« Nutrition », « Sommeil », « Poids », « Volume de la semaine », « Régularité », « Prochain objectif »,
« Demander au coach » and its Control Center button, « Scanner un produit » and its control —
`/nutrition/scan` opens Nutrition from Résumé with the scanner up, hidden with Nutrition; home screen
and lock screen). The snapshot is in
sections — `day` (verdict, sessions, last night's sleep) and `regularity` from Résumé's fold,
`nutrition` from the food log card (`NutritionTodayStore`), `weight` from Santé's body overview (`CorpsStore`) and the
profile's target, `training` (the last two weeks recorded) from Activité's list, `goal` (Objectifs'
next race, `GoalOrdering.nextRace`) from `GoalStore` — each written by the screen that reads it and
merged (`WidgetSnapshotStore.update`); the silent push reads them all. The volume widget is an
`AppIntentConfiguration` (`VolumeSport`): kilometres for one sport, time for strength or all sports,
Monday first, with last week at the same point as a fact, never a verdict. No streaks. `/goals`
opens Plan's Objectifs (`ShellRouter.isShowingGoals`). Every widget opens the page it stands for:
Sommeil `/sleep` and Nutrition `/nutrition` are pushed on Résumé (`ShellRouter.openToday`,
`TodayPage`), the verdict `/today` pops Résumé to its top; a locked widget opens SharpIt Pro
(`/settings/pro`), a hidden one Pages et widgets (`/settings/features`) — `WidgetSnapshot.link`
decides, tested in `WidgetLinkTests`. The app hears every URL (`IncomingLinkInbox`) and `RootView`
follows it once it shows, so a widget tapped on a cold launch, while the gates still check the
session, is not lost; Paramètres is closed first. How a section reads (the dial's figure, the target line) is in `WidgetSnapshotReadout`, shared
and tested; the energy and sleep dials are the app's `SharpitTickGauge` (`DialReadout`). A widget never calls the API — no Clerk session, a small reload
budget: the app writes a `WidgetSnapshot` into the App Group `group.app.sharpit.ios`
(`WidgetSnapshotStore`) from Résumé's fold each time it reads today, and on a silent push the
server sends after each scheduled sync (`refresh: today`), then reloads the timelines. A snapshot
of another day shows as stale, never as today; signing out or a new account erases it.
Every home-screen widget is built on `WidgetFrame` (`WidgetStyle.swift`): one header — its name
and one glyph, same height and gap on every widget — then the body anchored to the bottom, with one
type scale (`WidgetHero` for the main number, `WidgetTitle`, `WidgetCaption`) and `WidgetMetrics`;
a widget never lays out its own header. A widget is a card: it draws the card surface (white on light,
`#161618` on dark; ADR-085), no texture or halo, and speaks the app's SF Pro ramp. A session opens itself: `https://sharpit.app/activity/<id>` once done (Activité pushes its
detail), `/plan/session/<id>` before (Plan opens today's week and the session's drawer).
`SharpItShared/` is compiled into both targets: the generated tokens (`yarn tokens:ios` writes
there), the typography (SF Pro), `V1ActivityType` with its identity colour (ink, since ADR-085), `V1TodayPosture` with its tone, and the snapshot.
The target was added by hand to `project.pbxproj` (IDs `…05…`); its Info.plist and entitlements are
in `Config/`.

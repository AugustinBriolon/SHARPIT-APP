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
a widget never lays out its own header. A widget is an ink plate (`sharpitWidgetChrome()`: `inkSurface` behind, the content read in dark so
figures are white and captions muted), glyphs and marks in lime (`inkAccent`), as the app's lead card
and the Live Activities; no texture or halo, and the app's SF Pro ramp. A tinted or clear Home Screen
drops the plate and tints what is `widgetAccentable()`. A session opens itself: `https://sharpit.app/activity/<id>` once done (Activité pushes its
detail), `/plan/session/<id>` before (Plan opens today's week and the session's drawer).
`SharpItShared/` is compiled into both targets: the generated tokens (`yarn tokens:ios` writes
there), the typography (SF Pro), `V1ActivityType` with its identity colour (ink, since ADR-085), `V1TodayPosture` with its tone, and the snapshot.
The target was added by hand to `project.pbxproj` (IDs `…05…`); its Info.plist and entitlements are
in `Config/`.

**Clinique (2026-11-15).** The widgets left the ink plate for the app's sheet (`docs/adr/0035`):
`sharpitWidgetChrome()` is the card's white in the phone's own appearance, figures in ink, each
pillar's hue on its marks (`WidgetRing`, the header glyph), names in sentence case (`WidgetEyebrow`).
The tick dial is gone: `DialReadout` draws a score in its ring (sleep blue, recovery green, nutrition
orange). « Résumé » (`ResumeRingsWidget`, small and medium) is new: the day's four rings as the first
screen draws them (`WidgetResumeRing.rings`, in `SharpItShared`, tested), a hidden feature's ring
left out. « Récupération » (`RecoveryWidget`, `Day.recovery` from Résumé's gauge) takes the place
of « Réserve », a score Résumé's rings no longer carry; `Day.energyBank` stays decodable, unread.
Not seen on a Home Screen: the simulator's widget gallery was not driven.

**Verdict, Dernière activité: removed (the athlete's call, 2026-11-15).** Both widgets are gone
(little use, poor faces): the bundle no longer declares them, so one already placed shows the
system's empty tile until removed. The snapshot keeps `day.verdict` (Résumé's fold writes it; no
widget reads it) and lost `lastActivity` with its publisher; a stored `lastActivity` key is ignored
on decode, and `erase` still deletes the map PNG an earlier build wrote. « Résumé » small shows each
ring's glyph instead of its figure, and `WidgetRing`'s track fades on a tinted or clear Home Screen,
where an opaque track read as a full ring.

**Séance du jour square only, Dernière activité back (the athlete's call, 2026-11-16).** « Séance du
jour » lost its medium face (the day's sessions beside the verdict): it is the small square and the
Lock Screen ones. In its place, « Dernière activité » (`LatestActivityWidget`, medium and large,
free), laid out on the athlete's reference: the session's map runs to the widget's edge
(`contentMarginsDisabled`) with the route on it in red, start hollow, and fades into the sheet where
three figures stand, each under its name in capitals — « DISTANCE », « DURÉE », « ALLURE » (a ride's
« VITESSE », a swim's pace per 100 m; « CHARGE » when no distance was measured), time and pace read as
clocks (« 28:14 min », « 5:26 /km »). Nothing else is on the face — no title, no day: VoiceOver says
them. « Allure moyenne » was cut at a third of a medium widget, hence the one word. A widget cannot draw a map: the app draws them
(`LatestActivityMapImage`, `MKMapSnapshotter`, muted and turned to greys so the route is the only
hue), one per face and per appearance, beside the snapshot in the App Group
(`WidgetSnapshotStore.latestActivityMapURL`); `mapActivityId` says whose they are, so a new session
never shows the previous one's map. `RouteFraming` keeps the route above the figures. Without maps
the face keeps its shape on a plain plate with the route as a line (`WidgetRoute.fit`, a unit square
written in the snapshot); without a route, the sport's glyph. The snapshot's section is
`latestActivity`, never the old `lastActivity` key (another shape, still on some devices).
`WidgetSnapshotPublisher.publishLatestActivity` writes it from Activité's list and from the silent
push, once per session. `SharpitScreenDemo widgets` feeds it a session and its maps without an
account. Seen on the simulator's Home Screen, large, on that demo; the medium face
with a map and a real session were not seen.

**Clear and tinted Home Screens, latest activity on launch (2026-11-16).** There a colour keeps its
alpha only. « Dernière activité » draws the route alone (`PlainBackdrop`, no plate): the map was a
grey slab with its route lost in it and the fade a white block. Nutrition's macro track fades like
`WidgetRing`'s. `refreshLatestActivity` runs on launch and on each return to the app (`RootView`),
so the widget no longer waits for Activité to be opened. Seen on the simulator's Home Screen in
« Transparent », large; the other widgets were not seen there.

**Strength on « Séance du jour » (2026-11-17).** A strength session done shows the kilos lifted and
the number of exercises (`WidgetSnapshot.Day.figures`: the card's `kg` and `exos` metrics when both
are there, else its first two, as every other sport). The server sends them (`strengthVolumeMetric`,
sets × reps × load). Tested; not seen on a Home Screen.

**Strength on « Dernière activité » (2026-11-17).** The athlete meant this widget: a strength
session reads « DURÉE · VOLUME · EXERCICES » (kilos lifted, exercises done) from the list's
`strengthSets` (`V1ActivityListItem.strengthVolumeKg` / `strengthExerciseCount`); without a load it
keeps « CHARGE ». Tested; not seen on a Home Screen.

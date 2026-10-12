# Shell

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Shell.** `RootView` is a five-tab `TabView` (Résumé / Plan / Coach / Activité / Santé).
Paramètres is not a tab: it is a sheet (`SettingsView`) opened through `ShellRouter.openSettings()`
from the avatar (`AccountAvatarButton`, the Clerk photo or the initials) in Résumé's header, or a
`/settings` link. Résumé's date is its large title, folding into the centre of the bar on scroll as Santé's does;
the mode, Journal and weather are the fold's first row of glass chips (`sharpitGlassChip`) and
scroll away with it. Goals open from Plan's « … »
menu, the coach's memory (context, trips) from Coach's toolbar.

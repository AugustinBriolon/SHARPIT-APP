# Shell

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Shell.** `RootView` is a five-tab `TabView` (Résumé / Plan / Coach / Activité / Santé).
Paramètres is not a tab: it is a sheet (`SettingsView`) opened through `ShellRouter.openSettings()`
from the avatar (`AccountAvatarButton`, the Clerk photo or the initials) in Résumé's header, or a
`/settings` link. Résumé's date is its large title, folding into the centre of the bar on scroll as Santé's does;
the mode, Journal and weather are the fold's first row of glass chips (`sharpitGlassChip`) and
scroll away with it. Goals open from Plan's « … »
menu, the coach's memory (context, trips) from Coach's toolbar.

**Training mode.** The mode's chip (`ActivityStatusButton`) opens `ActivityStatusDrawer`
(`docs/adr/0036`): a title and a wheel of the four modes, nothing else. Turning the wheel writes the
mode, held until changed — no description, no length, no button, and no date on the chip (the
athlete's call, 2026-11-21: the mode is kept day by day). `ActivityStatusStore` shows the newest
write's answer only and falls back to the last store the server confirmed. On a past day of Résumé the chip
and the drawer carry that day (`day:`): they read it from `/api/v1/activity-status/days` and set it
after the fact (`apply(status:on:)`), leaving today's mode alone (SHARPIT ADR-150).

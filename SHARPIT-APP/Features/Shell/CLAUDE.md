# Shell

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Shell.** `RootView` is a five-tab `TabView` (Résumé / Plan / Coach / Activité / Santé).
Paramètres is not a tab: it is a sheet (`SettingsView`) opened through `ShellRouter.openSettings()`
from the avatar (`AccountAvatarButton`, the Clerk photo or the initials) in Résumé's header, or a
`/settings` link. Résumé's date is its large title, folding into the centre of the bar on scroll as Santé's does;
the mode, Journal and weather are the fold's first row of glass chips (`sharpitGlassChip`) and
scroll away with it. Goals open from Plan's « … »
menu, the coach's memory (context, trips) from Coach's toolbar.

**Training mode.** The mode's chip (`ActivityStatusButton`) and the line under Résumé's verdict
(`ActivityStatusAlertLine`) both open `ActivityStatusDrawer` (`docs/adr/0036`): the mode as a glyph in
a ring and a status pill with « Reprise dans 9 jours », the four modes as tiles, « Ce que ça change »
(two lines per mode, the web's `planningImpact` and nothing more), the length on chips that all write
the wire's one `until_date` (`ActivityStatusDuration`), « Reprendre l'entraînement » in ink. The copy
and the day maths are pure (`ActivityStatusReadout`). The drawer keeps what the athlete set and reads
the store back only on a refused write; `ActivityStatusStore` shows the newest write's answer only
and falls back to the last store the server confirmed. The chip keeps `tone`: it sits on the dark backdrop.

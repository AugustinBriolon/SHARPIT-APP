# Journal

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Journal.** `JournalView` asks for the day signals the athlete turned on, and
`JournalPrefsDrawer` chooses them. Preferences are kept as the raw JSON the server sent
(`JournalPrefs.raw`): the web stores keys the app does not model — nutrition panel,
thresholds — and the server rebuilds its enable map from defaults for every key a
payload omits, so sending back only what the app renders would silently reset the rest. The
catalogue in `JournalTrackables.swift` therefore covers the signals the app can render, never
all of the web's. The diets (`diet_*`, kind `.diet`) sit in the drawer's Nutrition section and draw
no row on the day: Nutrition's header names them and the coach reads the food against them.
« Conduite » (`metric_driving`, Style de vie, off by default) records the minutes driven
(`drivingMinutes`, a column of the day like caffeine and hydration), set in `DrivingInputSheet` by
quarter hours.

Humeur reads the morning check-in (`/api/v1/wellness-checkin`) when the journal row carries no mood — the mood lives there, the row only echoes it when answered from the journal; a day with only a check-in counts as noted, here and in the server's journal data days. The day picker marks the journal as the day screens mark their data (`SharpitDataDayMark`): a dot where something was noted, a ring where the day was read and holds nothing, nothing while unknown — from `/api/v1/data-days?domain=journal`. The journal and the day screens read their marks through one `DataDaysMarker`: the 91-day window holding the week in view first (the strip scrolled back, a month opened), then the rest of the history in a task of its own that a screen left mid-way does not cancel; a window that failed is read again when next needed. The journal's skeleton is its own rows redacted, under a date picker that stays put — only until the preferences are first known: after that a day not read yet is drawn as the athlete's own rows with only their values redacted and nothing tappable (`JournalStore.isReadingDay`, `journalValuesPending`), the neighbouring page of a swipe too. A day that fails to load says so under the picker, never in its place; a painted day that fails to refresh keeps its rows and says it in a toast.

The journal's toolbar opens « Analyses » (`JournalAnalysesView`, `JournalAnalysesStore` owned by
`JournalView`): what the habits go with, from `/api/v1/journal/analyses` (the web's own reading,
never computed here). Closed with its progress until seven days carry a signal; then the verdict
on the ink plate, « Ce qui t'aide », « Ce qui te freine » and « Pistes à confirmer », one card per
outcome (Sommeil, Récupération, Body Battery), each habit a dumbbell on the domain's shared axis
(`SharpitDumbbellTrack`: the median without, the median with, the days behind them, dashed when
weak), and the footer says an association is not a cause. No 7-day habit test: left out on purpose (2026-10-06).

Sections follow *when* a signal happened, not what kind of thing it is: Journée (the three
metrics), Checklist auto, Nuit dernière, Signaux du jour. `JournalDayWindow` is its own axis
beside `JournalCategory`, which still drives the drawer's filters — the web separates them
too, so one cannot be derived from the other. The automatic checklist is read from
`/api/journal/day-signals` and never recomputed: the thresholds, the sports that count as
cardio and the minutes summed per activity all live in the web's `journal-auto-checklist.ts`,
and a second implementation would diverge the first time a threshold moved. Its lines are
read-only, so they carry no toggle and no chevron, and the route is called only when the
athlete enabled one.

**Clinique.** The journal follows its mock-up (`docs/adr/0035`): « Choisir mes signaux » in the bar,
« Journal » as the page's title, and under it the day (it opens the calendar; a swipe turns the day —
the week strip is gone) with « 3 signaux sur 5 notés » (`JournalReadout.progress`). One table split by
hairlines (`JournalLines`, `JournalLine`), in the order the day was lived, without section names: the
mood first (a pill, read from the morning), caffeine stepped in place by 80 mg (`JournalStepper`; the
words still open the sheet with its presets), water with « + 25 cl », driving, the automatic checklist
(a check, read-only), the night's signals (« Cette nuit ») then the day's. A yes / no signal is one
capsule a tap walks through — « À noter », « Oui », « Non » (`JournalFactorLine`, `JournalStore.cycle`).
« Ce que ton journal montre » closes the page with the analyses' headline and opens them.
`SharpitScreenDemo journal` shows it. « Ton ressenti ce matin » (`RessentiDuJourSheet`) is five bordered
tiles, as many bars as the step (`RessentiStepPicker`), details on five dashes (`RessentiScaleRow`),
« Enregistrer » and « Plus tard » under them; `SharpitScreenDemo ressenti`.

**Analyses, Clinique.** `JournalAnalysesView` takes the sleep wash and the large title; « À retenir »
is a bordered card — the sentence to act on, what it rests on, what already holds — and each
outcome's habits stay dumbbells under their titles. `SharpitScreenDemo analyses` shows it.

« Mes signaux » (`JournalPrefsDrawer`) filters with the app's chips — ink once chosen, a hairline
otherwise — and titles each group.

**Second pass (the athlete's call, 2026-11-15).** The day is titled groups again — « Journée »,
« Mesuré pour toi », « Nuit dernière », « Signaux du jour » (`JournalGroup`) — each line opening on
its glyph. A signal shows both answers (« Non » / « Oui », `JournalFactorLine`): a tap gives one, a
second tap on it takes it back (`JournalReadout.tapped`); the cycling capsule is gone.

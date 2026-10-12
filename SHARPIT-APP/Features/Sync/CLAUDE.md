# Freshness and sources

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Freshness.** The app starts provider pulls itself (`ProviderSyncStore`, `/api/v1/sync`)
on launch, foreground and pull-to-refresh, and can send Apple Health day summaries
(`AppleHealthSource`, `/api/v1/health-samples`) when the athlete switches it on in Paramètres → Sources de données.
The regular pull only reaches back to the last one, so `GarminHistoryImport` runs the web's
full-history Garmin import once per Clerk user, the first time Garmin is seen connected
(launch, foreground, or the Garmin handoff). It is remembered only once it finished; a run cut
off by the server's five-minute limit is picked up on the next foreground, and the server skips
what it already holds. Streams are not in that pass: `/api/v1/sync` backfills them a batch at a
time. Apple Health only fills gaps; Garmin stays the reference (`docs/adr/0005`, SHARPIT
ADR-043) — yet it is enough on its own: an Apple Watch without Garmin gets the whole app.
Switching it on sends the last year, then each sync sends what came in since, a marker per kind
and per account moving forward batch by batch (so a send cut short picks up where it stopped):
the days (`/api/v1/health-samples`, 31 per call, the last week always re-sent; the server turns
them into the Core's sleep, HRV and resting-HR observations) and the workouts
(`/api/v1/health-workouts`, five per call, a month read at a time — `HealthWorkout`, its heart
rate and route laid on one 5-second axis by `HealthWorkoutStreamBuilder`). The server stores a
workout while Apple Health is enabled for activities in the athlete's sources; it answers
`acceptsWorkouts: false` otherwise and the app stops sending them. Apple Health is a source like
the others (SHARPIT ADR-054): its switch links it on the web (`/api/v1/apple-health/link`), and
Sources de données › Priorités par catégorie (`SourcePrioritiesView`, `SourcePrefsStore`,
`/api/v1/integrations/source-prefs`) turns each connected source on or off per data class and picks
the primary — the web applies it: the primary's values win, the others fill what it lacks. HealthKit is read-only and entitled in `SharpIt.entitlements`. A night or a workout written to Health wakes the
app (`HealthUploadObserver`: an `HKObserverQuery` per type with background delivery, registered in
`SharpitAppDelegate` at every launch, one send at a time) and is sent at once, so the server sends
the morning verdict as soon as the night is read and « Séance dans la boîte » once a workout counts
for a planned session. Paramètres → Sources de données also offers the import on demand
(`GarminHistoryImport.importAll`), whether or not a run already finished.

A connected source is disconnected from its row in Sources de données (`DisconnectableSource`:
Garmin where `ProviderAvailability` shows it, Withings and Google Agenda whenever
`/api/v1/sync-status` lists them): the tap asks first — a confirmation naming what stops and what
stays, in the web's words (« Déconnecter Withings ? ») — then `SourceDisconnectClient` posts
`/api/v1/{garmin,withings,google}/disconnect` through `SharpitRetry` and waits for it, since the
server revokes the grant at the provider; the list is read again and a toast says it. Withings and
Google Agenda are still connected on the web only — their OAuth return lands on the web's settings,
not on an Associated Domains path an authentication session can close on — and the section's footer
says so (`ConnectionsReadout.webSourcesFooter`).

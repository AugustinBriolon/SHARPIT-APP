# Freshness and sources

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**Freshness.** The app starts provider pulls itself (`ProviderSyncStore`, `/api/v1/sync`)
on launch, foreground and pull-to-refresh, and can send Apple Health day summaries
(`AppleHealthSource`, `/api/v1/health-samples`) when the athlete switches it on in Paramètres → Sources de données.
The app links no Garmin account (`docs/adr/0013`): a Garmin watch reaches SHARPIT through Apple
Health, or through an account linked on the web, which the server keeps pulling. Apple Health only
fills gaps where a richer source is linked (`docs/adr/0005`, SHARPIT ADR-043) — yet it is enough on
its own: an Apple Watch alone gets the whole app.
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
for a planned session.

A connected source is disconnected from its row in Sources de données (`DisconnectableSource`:
Strava, Withings and Google Agenda whenever `/api/v1/sync-status` lists them): the tap asks first — a confirmation naming what stops and what
stays, in the web's words (« Déconnecter Withings ? ») — then `SourceDisconnectClient` posts
`/api/v1/{strava,withings,google}/disconnect` through `SharpitRetry` and waits for it, since the
server revokes the grant at the provider; the list is read again and a toast says it. They
connect in-app in an authentication session (`ProviderOAuthConnect` /
`POST /api/v1/<source>/handoff`, SHARPIT ADR-047); the footer says so (`ConnectionsReadout.sourcesFooter`).

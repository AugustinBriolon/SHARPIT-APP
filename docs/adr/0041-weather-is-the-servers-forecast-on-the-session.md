# 41. Weather is the server's forecast, shown on the session

Date: 2026-11-26

## Status

Accepted.

## Context

Résumé carried a weather chip: the temperature where the athlete stood, read on the iPhone from
WeatherKit and Core Location. Nothing else read it — not the verdict, not the coach, not the plan —
and WeatherKit made it costly: an entitlement, Apple Weather's mark and legal link wherever its data
shows, a location prompt and a Precise Location line in the privacy manifest. App Review rejected
1.0 over that attribution (2026-11-26).

The weather the athlete needs is a session's, not the street's: heat before a threshold run, rain on
a ride, cold on a long outing. The server already holds it. For every planned session it reads the
Open-Meteo forecast of the session's slot and place (`resolvePlannedSessionContext`, refreshed by the
`planned-forecast` cron and on every change), derives advisories from it (`buildPlannedSessionAdvisories`:
reduce intensity, go earlier, drink more, indoor option, harder recovery, rain, cold) and stores them
as `environmentContext` on the session, which `/api/v1/planned-sessions` already returns. After the
session, the activity's observed weather feeds its environmental correction and the coach's analysis.

## Decision

We will show the server's forecast on the session and read no weather on the iPhone.

- The WeatherKit chip, its service, the WeatherKit entitlement, the location usage string and the
  manifest's Precise Location entry are removed. `theAppAsksForNeitherWeatherKitNorLocation` keeps
  them out.
- `V1PlannedSessionItem` decodes `environmentContext` into `V1SessionConditions`: the advisories
  that change what the athlete does, in the server's order. « Conditions favorables », « séance en
  intérieur », « prévision indisponible » and the location question are left out: nothing to act on.
- The session's drawer shows them under « Météo prévue », after the figures and before the steps —
  a glyph, what to do, why — in Plan and in Résumé, whose drawer reads the session from the plan.
  Ink only: the advice is the content, not a status.
- Only for a session still to do (today or later, not done). A local edit that moves the day or
  changes the sport drops the forecast until the server reads it again.
- The words are the web's (`presentation/planned-session`), in « tu »; rain and cold also say to
  take care on slippery or icy ground.

## Consequences

- One fewer permission prompt and one fewer collected data type; App Privacy in App Store Connect
  must drop Precise Location to match the manifest.
- The advice copy lives twice, on the web and here, as every native mapping of a domain code does
  (SHARPIT ADR-040: native never calls `/api/presentation/*`). A new advisory kind is ignored by the
  app until it is mapped.
- Open-Meteo's free API is for non-commercial use; with SharpIt Pro on sale the server needs its
  commercial plan (a server matter, not the app's).
- The plan is advised, not changed: no « Alléger » is proposed from the weather alone yet.

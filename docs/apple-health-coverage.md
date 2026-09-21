# Garmin → Apple Health coverage

Measured on 2026-09-21 with the app's own diagnostic (Moi → Diagnostic Apple Santé): fourteen
days of Apple Health on the athlete's iPhone, Garmin watch synced through Garmin Connect.
The results are the athlete's report of the diagnostic's verdicts, not an export.

| Signal | Verdict | Used for |
|---|---|---|
| Sleep duration | covered | Sleep |
| Sleep stages | covered | Sleep |
| Resting heart rate | covered | Recovery |
| Heart rate | covered | Activity |
| Steps | covered | Daily load |
| Active energy | covered | Daily load |
| Workouts | covered | Activity |
| Weight | partial | Body |
| HRV | missing | Recovery |
| Respiration | missing | Health |
| SpO₂ | missing | Health |
| VO₂ max | missing | Fitness |
| Workout routes | missing | Activity |
| Body Battery, stress, Training Readiness, Garmin sleep score | no equivalent | Recovery, daily load, sleep |

## Reading it

- **Matches ADR 0005 and SHARPIT ADR-043.** What the app sends to `/api/v1/health-samples`
  — sleep and stages, bed and wake time, resting heart rate, steps, energy, weight — is
  what Apple Health holds. Resting heart rate, which was uncertain, is confirmed.
- **Weight is partial because it is sparse, not because it is missing.** It is logged when
  the scale is used; a half circle here is not a gap.
- **HRV, readiness and Body Battery only come from the server's Garmin pull.** The recovery
  screen's autonomic dimension therefore depends on `/api/v1/sync` succeeding, whatever the
  Apple Health switch says.
- **Workouts are present but stay out of the upload.** Without routes or streams they would
  duplicate the Garmin activities the server already holds, with less in them. They matter
  only for an athlete with no Garmin.
- Apple Health cannot say whether a type was refused; a "missing" row can also mean access
  was not granted. Rerun the diagnostic after changing access in Réglages › Santé.

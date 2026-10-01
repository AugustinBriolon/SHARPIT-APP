# 10. Import the MyFitnessPal export instead of linking it

Date: 2026-10-01

## Status

Accepted

## Context

The iPhone app linked MyFitnessPal in three places: Sources de données, the onboarding's Sources
step and Nutrition's « … » menu. `MyFitnessPalConnectSheet` opened MyFitnessPal's sign-in page in a
private web view, read the next-auth session cookie once the athlete was signed in, and posted it
to `/api/v1/myfitnesspal/connect`; Nutrition then pulled the diary through
`/api/v1/myfitnesspal/sync` on demand and on opening past 15 minutes.

MyFitnessPal offers no public API for this. The cookie gives SHARPIT access to a third-party
service through its private web endpoints, without that service's authorisation. App Review
guideline 5.2.2 requires an app that uses or displays a third-party service to be permitted to do
so under its terms, and the same reasoning already took Garmin out of the App Store build
(`ProviderAvailability.garminInApp`). A rejection on this point would block the launch.

The food log itself no longer depends on MyFitnessPal: since SHARPIT ADR-061 the athlete logs meals
in SHARPIT (search, Open Food Facts barcodes, own foods, quick add). What MyFitnessPal still holds is
the athlete's history, and MyFitnessPal Premium lets the athlete export it themselves: Rapports →
Exporter mails a ZIP with one CSV row per meal and day. The export carries each meal's totals, not
its foods.

## Decision

- **The iPhone app never links, syncs or unlinks MyFitnessPal.** No row in Sources de données, no
  onboarding card, no sync in Nutrition, no expired-session alert. `MyFitnessPalConnectSheet`,
  `MyFitnessPalServing`, the three `SharpitClient` methods and `V1MyFitnessPalConnect` are removed,
  and the app no longer reads `mfpConnected`. A test asserts no source file calls the
  `/api/v1/myfitnesspal` routes or opens `myfitnesspal.com`.
- **The athlete imports their own export instead.** Nutrition's « … » menu ends with « Importer
  depuis MyFitnessPal »: a sheet explains the export, opens the Files picker (ZIP, CSV or plain
  text, at most 4 MB) and posts the file as `multipart/form-data` to
  `/api/v1/food-log/import/myfitnesspal`. The server parses it and writes each meal's total, day by
  day; the sheet says how many days came in and over which dates, or the server's own refusal.
- **Imported days read as before.** A day with no entry of its own shows its imported meals
  read-only (`NutritionMealsMode.imported`); the day's own log wins once it holds an entry. Days an
  account linked on the web keeps syncing server-side show the same way.

## Options considered

### Option A — Keep the in-app sign-in behind a switch, off for the App Store
As Garmin does with `ProviderAvailability`. Pros: one flag to turn it back on. Cons: MyFitnessPal
has no official programme to wait for, so the switch would never flip; the dead code would keep a
web view harvesting a third-party session cookie in the binary, which is exactly what review reads.

### Option B — Send athletes to the web to link MyFitnessPal
Pros: the history keeps flowing for those who link. Cons: steering iPhone users towards an
unofficial access is the same exposure, one hop removed; the web's own exposure is a separate
decision for the web repository.

### Option C — Import the athlete's own export file (chosen)
Pros: the athlete moves their own data, through MyFitnessPal's own export feature, which complies by
construction; no credentials or cookies pass through SHARPIT; the history arrives in one step.
Cons: only meal totals, not foods; the export needs MyFitnessPal Premium; new days are not pulled
afterwards, the athlete logs them in SHARPIT.

## Consequences

### Positive
- Nothing in the binary signs in to a service without its authorisation; one fewer web view and
  data flow to explain at review.
- Moving from MyFitnessPal to the in-app log becomes one import rather than a standing link.

### Negative
- Imported days list meals with their totals only: no food to edit or re-log.
- Athletes without MyFitnessPal Premium cannot export, so cannot import.
- An athlete who linked MyFitnessPal from the app can no longer sync or unlink it from the iPhone;
  the link, if kept, lives on the web.

### Neutral
- `ProviderLogo` keeps its MyFitnessPal case: the web still lists the provider in Priorités par
  catégorie for accounts that hold its data.
- The import posts `multipart/form-data` with a 90-second timeout; it is not retried, since a second
  upload of the same file would only meet the rate limit.

## References
- `SHARPIT-APP/Features/Nutrition/MyFitnessPalImport.swift` — the sheet, its store and its readout
- `SHARPIT-APP/Networking/MultipartFormData.swift` — the request body
- `SHARPIT-APP/Features/Connections/ProviderAvailability.swift` — the same reasoning for Garmin
- SHARPIT ADR-061 — the food log lives in SHARPIT
- https://developer.apple.com/app-store/review/guidelines/#intellectual-property — guideline 5.2.2

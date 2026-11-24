# 38. A known structure is never a skeleton, and kept answers paint first

Date: 2026-11-24

## Status

Accepted

## Context

The Nutrition page drew its four meals redacted on every visit. The meals are fixed in the app
(`FoodLogMeal.allCases`): only what each holds comes from the server. `FoodLogStore` was built
anew with the page and kept nothing, so leaving the page and coming back read the day again under
a skeleton, while the rest of the page already painted from `DayReadCache` (`docs/adr/0021`).

The athlete's remark (2026-11-24): a list known in advance has no reason to load, a value may,
and a page left and opened again must not load twice. The same held for Objectifs (no kept
answer), Analyses de sang (a second store beside Santé's, read again under a skeleton) and
Matériel (redacted until the server answered, with the profile already kept on the iPhone).

## Decision

We will draw what the app knows without the server at once, and paint the last answer kept on
the iPhone before reading again.

- A structure fixed in the app is drawn as itself while its values are read: the four meals keep
  their glyph and name, and only a meal's energy is redacted (`FoodLogMealRow.isLoading`).
- `FoodLogStore` keeps each day in `ResponseCache` (`ResponseCacheKey.foodLogDay`) and paints it
  in its `init` and on a change of day. It is written again from the server's answer and after
  every write the server took, without the rows still on their way. A score is kept only with
  the entries the server scored.
- `GoalStore.load(keptIn:)` paints the goals last read (`ResponseCacheKey.goals`) on its first
  read and keeps the goals on every change, a write's included. A refresh that fails under them
  is a toast, and a kept empty list is not a skeleton.
- `BloodTestsView` takes the store Santé already read instead of building its own, and
  `BloodTestsStore` keeps the tests on every change (`ResponseCacheKey.bloodTests`): they paint
  after a relaunch, offline too.
- `CoachView` holds one `CoachHistoryStore` for the tab; reopened, the list stands while it is
  read again, and when that read fails.
- The other pages that redacted names the app already knew keep them sharp: the journal's own
  lines (`journalNamesStaySharp`, the answers alone wait), the kinds of notification, Priorités'
  classes, the sleep targets' cards, Matériel and Analyses de sang.
- `AthleteProfileStore.keptProfile()` hands the profile kept on the iPhone to a page that draws
  it on its first frame, without making the store `loaded`. `EquipmentView` fills from it at once
  and takes the server's profile when it arrives, unless the athlete already changed something
  on the page.

The kept answers live in the `CachedResponse` table, which stays on the iPhone
(`docs/adr/0009`) and is wiped with the account (`LocalAccountData`).

## Options considered

- **Keep the food log in memory only, in a shared store.** Survives a revisit, not a relaunch,
  and a second owner of the day's entries beside the page. Rejected: `ResponseCache` already
  exists for this and covers both.
- **Keep the server's raw bytes** as `DayReadCache` does. The store changes the day on every
  write, so the bytes would be stale after the first food added. Rejected: `V1FoodLogDay`
  becomes `Codable` and the store keeps what it shows.
- **Share Santé's store and keep nothing of the blood tests.** First chosen, to avoid another
  copy of health data. It left the page failing after a relaunch offline, so the tests are kept
  after all, in the same on-device table as the rest (`docs/adr/0009`).

## Consequences

- A visit to Nutrition, Objectifs, Analyses de sang or Matériel after a first read shows content
  on its first frame, offline and after a relaunch included; a refresh that fails under it stays
  quiet or is a toast.
- Three skeletons are still grey blocks of guessed sizes, against the root rule, each seen only
  on a first read ever: Plan's (`PlanLoadingView`), the day screens' (`DayDetailSkeleton`) and
  Corps' chart (`CorpsDrawer`).
- A skeleton remains only where nothing was ever read, and there it redacts values, not names.
- The forms that wait for the profile before they can be edited (`SettingsPages`, `TargetSheets`)
  keep their wait: they write what they show, and must not start from a stale value.
- Matériel can be edited on the kept profile for the moment the read takes. A change made
  elsewhere in that moment would be overwritten by the page's save.
- A wire type the app keeps must stay decodable from its older shape; an answer it can no longer
  decode reads as absent.

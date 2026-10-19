# 19. The app speaks French and English from one String Catalog

Date: 2026-10-19

## Status

Accepted

## Context

SharpIt goes on the App Store worldwide. Every screen, widget, Live Activity and permission prompt
was written in French, straight in the Swift source: about 2,500 distinct strings, of which only
~400 sat in `Text("…")` (which SwiftUI localizes on its own). The rest were Strings built in
readouts, stores, networking errors and design-system helpers taking `title: String`, which
`Text(String)` shows verbatim. Dates and numbers were pinned to `fr_FR` in 38 files, and the root
view forced `\.locale` to `fr_FR`.

The athlete must also be able to pick the language in Paramètres, and the server must know it, so
that pushes, coach answers and server copy follow (SHARPIT-WEBAPP ADR-096).

## Decision

- **One catalog, French keys.** `SharpItShared/Localizable.xcstrings` (built into the app and the
  widget extension) holds every string. The key is the French copy as it stands in the code, so the
  source keeps reading as the product's French; each key carries an explicit `fr` value (equal to
  the key) and an `en` value. Model-built copy is wrapped in `String(localized:)`; SwiftUI's
  `LocalizedStringKey` initialisers and App Intents' `LocalizedStringResource` are left as they are.
  `SHARPIT-APP/InfoPlist.xcstrings` localizes the permission prompts.
- **English is the development region.** The project's `developmentRegion` and the catalogs'
  `sourceLanguage` are `en`: iOS falls back to the development region when none of the device's
  languages is supported, so a German or Japanese iPhone gets English, not French.
- **The pick is the bundle's `AppleLanguages`.** Paramètres → Langue offers the device's language,
  Français or English, and writes the app domain's `AppleLanguages` (`AppLanguage.choose`) — the key
  iOS's own per-app Language setting writes, so both stay in step. A bundle resolves its language
  once per process: the page says to reopen SharpIt, rather than half-switching the screens already
  loaded. The widget extension adopts the language the app published to the App Group.
- **The locale follows the language.** `AppLanguage.locale` (the shown language with the device's
  region) replaces every `fr_FR`, through `SharpitLocale.current` and the root `\.locale`.
- **The profile knows it.** On each launch `AppLanguage.syncToProfile` PATCHes `locale` (`fr`/`en`)
  when the profile holds another one, and a pick of French or English PATCHes it at once.
- **Tests run in French** (`language = "fr"` on the scheme's test action), so existing expectations
  on French copy hold; `LocalizationTests` fails on a catalog key without an `en` or `fr` value.

## Options considered

### Option A — `String(localized:)` with French keys (chosen)
Mechanical wrap of the existing literals (a script, then the compiler for the few typed contexts),
translations added in the catalog. Pros: the source stays readable French, no 2,500 invented key
names, Xcode's export/import works. Cons: changing French copy changes the key, so its English must
be re-entered; interpolated Doubles would print with `%lf` (none seen on screen).

### Option B — Semantic keys (`today.verdict.title`)
Pros: copy edits don't break keys. Cons: rewriting every call site by hand, and the source no
longer shows what the athlete reads — against how this codebase is reviewed.

### Option C — Leave the language to iOS Settings only
Pros: no code. Cons: the athlete asked for the choice in Paramètres, and the server would only
learn the language from request headers, never for pushes sent without a request.

### Option D — Switch language live, without a relaunch
Pros: instant. Cons: `Bundle` lookups are fixed per process; it would need a custom bundle swizzle
and a re-render of every cached String (readouts, snapshots, widgets). Not worth it for a setting
changed once.

## Consequences

### Positive
- The app, its widgets, Live Activities and permission prompts are fully usable in English.
- Unsupported device languages get English instead of French.
- Pushes and coach answers can follow the athlete's language (server ADR-096).

### Negative
- Editing a French string orphans its English: `LocalizationTests` catches the missing value, and
  the new key must be translated in the catalog.
- Copy compared against server text (a few parsers of French coach output) does not localize; it is
  listed for the server side to send codes instead.
- Changing the language needs a relaunch.

### Neutral
- Onboarding copy is wrapped in a follow-up, once a parallel change to those files has landed.

## References
- SHARPIT-WEBAPP ADR-096 — athlete locale on the server
- `docs/app-store-submission.md` — App Store Connect localization

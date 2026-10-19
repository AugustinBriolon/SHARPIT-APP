# Pro-only coaching and the onboarding paywall: implementation plan

**Date:** 2026-10-19
**Decision:** SHARPIT-WEBAPP [ADR-097](../../../../SHARPIT-WEBAPP/docs/adr/ADR-097-free-is-the-athletes-data-coaching-is-pro-only.md)
(Accepted 2026-10-19).
**Repos:** SHARPIT-WEBAPP (server, web) and SHARPIT-APP (iOS). Work on `main`. A push to the web
repo deploys prod, so the server steps ship before the iOS build that relies on them.

## Target flow

```
Welcome → profile (identity → injuries, on the phone) → Sign in with Apple / e-mail
  → legal wall → privacy → sources → first week streams in (preview)
  → ~2 s readable → blur + paywall sheet (monthly −50 % first month, yearly)
      ├─ subscribe → week inserted → Résumé (Pro)
      └─ close     → onboarding complete → Résumé (Free: data only)
```

## Free / Pro boundary

| Surface | Free | Pro |
|---|---|---|
| Activities, health, sleep, body, journal, manual food log, calendar | ✅ | ✅ |
| Deterministic readouts already shipped (load, recovery, sleep) | ✅ | ✅ |
| Sessions already in the plan (read, edit, delete, mark done) | ✅ | ✅ |
| Week generation (`coach/plan`) | onboarding preview only | ✅ |
| Coach chat, adapt, morning proposal, daily briefing | ❌ | ✅ |
| Session analysis, weekly review, nutrition reading, meal description | ❌ | ✅ |
| Automatic next week (ADR-095 `plan-horizon`) | ❌ | ✅ |
| Existing extras (biological age, watch push, widgets, early access) | ❌ | ✅ |

---

## Step 1 — App Store Connect and StoreKit config (no code)

1. App Store Connect → subscription group « SharpIt Pro » → `app.sharpit.ios.pro.monthly` →
   Introductory Offer: *Pay as you go*, 1 month, 50 % of the price, all territories.
2. `SHARPIT-APP/Config/SharpitPro.storekit`: set the same `introductoryOffer` on the monthly
   product (currently `null`, line 36) so the simulator shows it.
3. Check that the App Store description says the coach needs a subscription.

**Done when** `SubscriptionStoreView` in the simulator shows the discounted first month.

## Step 2 — Server: one `pro_required` gate (SHARPIT-WEBAPP)

> **Done 2026-10-19, with these changes to the plan below:** the refusal is
> `403 { error: 'pro_required' }` (the watch push's existing shape, which iOS already reads).
> The Free budget stays at 50 000 tokens as the preview's cap and `coach/quota` answers zero
> questions for Free. The rule-based adaptation and morning proposal call no model, so they stay
> Free. Compliance and brick analysis are gated too. The briefing falls back to its deterministic
> text for Free. The web carnet calls no coaching route, so 2.6 needed nothing. `food-log/describe`
> and the weekly review were already Pro and are unchanged.

1. `packages/server/src/lib/access/require-pro.ts` (new, small): `requirePro(athleteId)` returns
   `null` or a `403 { error, code: 'pro_required' }` response. It reuses `isProAthlete`, and the
   copy comes from the server copy catalog (ADR-096).
2. Gate these handlers with it, before any LLM work:
   - `handlers/coach/chat`, `coach/adapt`, `coach/briefing`, `coach/weekly-review` (already
     checks Pro, so align it on `requirePro`);
   - `handlers/coach/plan`, which has the onboarding exception: a Free athlete passes when
     `onboardingCompletedAt` is null and no plan job was started before. Week insertion
     (`insertGeneratedWeek` route) is Pro-only;
   - `handlers/v1/adaptation` (morning proposal);
   - activity narrative (`lib/activity/narrative`): replace the `narrative-trial.ts` checks with
     Pro-only and delete `FREE_NARRATIVE_DAILY_LIMIT` / `isActivityFreeEligible`;
   - `food-log/describe` and nutrition reading: switch to `requirePro`, which also gives them the
     shared code.
3. `ai-budget-shared.ts`: set the Free daily budget to 0, so `coach/quota` answers
   `dailyQuestions: 0` for Free. Keep the Pro budget at 500 000.
4. Background and crons skip Free athletes:
   - `cron/plan-horizon` (ADR-095): add a Pro filter to the athlete query;
   - `athlete-state/background` and `snapshot-service`: only generate the daily briefing for Pro;
   - `cron/morning-push` and `cron/planned-forecast`: check whether they call an LLM. If they do,
     skip Free; if not, leave them alone.
5. `packages/app/src/lib/access/pro-perks.ts`: lead with « Coach », « Plan qui s'adapte » and
   « Analyse de séance », and fold `extended-coach` into « Coach ». Add the English copy to
   `copy-en.json`.
6. Web (`apps/web`): wherever a route can now return `pro_required`, show a « Disponible avec
   SharpIt Pro, depuis l'app iPhone » state instead of an error. There is no Stripe yet.

**Tests (Vitest):** `require-pro.test.ts`. For each gated handler, Free → 403 `pro_required`
with the LLM client never called, and Pro → unchanged. Plan handler: Free during onboarding gets
one job, a second one → 403, and an insert → 403. `plan-horizon` skips Free. Delete
`narrative-trial.test.ts` and replace it with Pro-only tests. Update `ai-budget` and quota tests.

**Before pushing:** give every TestFlight tester a `manual` entitlement from `/admin`, otherwise
they lose the coach the moment the deploy lands. This step ships alone, before the iOS build.

## Step 3 — iOS: `pro_required` becomes an upsell, not an error

1. `SharpitAPIError`: add `case proRequired`, decoded from `code: 'pro_required'` where the
   client maps 403s.
2. Every surface that can hit it shows `SharpitProTeaser`, which already exists, instead of the
   error text: Coach composer, week generator (Plan), adaptation and morning proposal on Today,
   session analysis, weekly review, food describe, nutrition reading.
3. Free Résumé and Today must not leave empty coach slots. Where the briefing or the proposal is
   missing for a Free athlete, show the data and one teaser.
4. Coach tab for Free: `CoachQuotaReadout` / `CoachUsageSheet` with `dailyQuestions == 0` turns
   into a single teaser.

**Tests (Swift Testing):** error decoding (`pro_required` → `.proRequired`). Store tests for
coach, plan generator and today: `.proRequired` → teaser state, not `.failed`. Update
`CoachQuotaTests`.

## Step 4 — iOS: profile before the account

Today `AuthGate` → `AccountGate` → wizard, and each step writes to the server through
`OnboardingStore.enqueue` / `flushWrites` (`OnboardingStore.swift:384-424`).

1. **A Codable draft** `OnboardingDraft` holds identity, motivation, sports, equipment, week,
   goal input and injuries. It is saved to a file in Application Support (excluded from backups,
   iOS ADR 0017) on every step, so a quit does not lose the answers.
2. **Pre-account wizard:** `AuthGate` shows Welcome → « Commencer » → the profile steps
   (identity … injuries) without a token. `OnboardingStore` gets a mode where the `leave*`
   methods only update the draft. The welcome screen keeps a « J'ai déjà un compte » link that
   goes straight to sign-in.
3. **Sign-up step:** after injuries, `SharpitAuthDrawer` (Apple + e-mail, already there) opens as
   a step of the wizard, with the header « Crée ton compte pour que le coach écrive ta semaine ».
4. **Replay:** once Clerk has a session, `AccountGate` builds the store from the draft, shows the
   legal wall, then replays the draft through the existing writes (`saveFirstName`, profile
   patch, `createGoal`, physical notes) with `flushWrites`, in the same order as today. The draft
   file is deleted once `flushWrites` returns true.
5. **Then** privacy → sources → first week, unchanged.
6. **An existing account that signs in** from the welcome screen skips the draft. Its server
   profile wins, which is the current behaviour.

**Tests:** draft round-trip (encode, decode, file excluded from backup). A pre-account step makes
no network call (fake services assert zero calls). Replay writes everything in order and deletes
the draft. A failed replay keeps the draft and shows the retry. A sign-in from the welcome screen
ignores a stale draft. Update `AccountGate` tests for the new order.

## Step 5 — iOS: blurred week and the paywall

1. `OnboardingFirstWeekStep` (`OnboardingSteps.swift:648`): when the athlete is Free and
   `firstWeek == .ready`, wait about 2 s (skip the wait under Reduce Motion), then
   `.blur(radius:)` the session list with `SharpitMotion.reveal`, and present the paywall sheet.
   Pro athletes (restore, an existing subscriber) keep today's « Ajouter » path.
2. The paywall reuses `ProView.paywall` (`ProView.swift:112`) and the `ProStore` of the session.
   `appAccountToken` exists because the account was created in step 4. Its title is « Ta semaine
   est prête », and it keeps restore, terms and privacy (`SubscriptionStoreView`'s own controls).
3. **Purchase completes** → `ProStore` verifies with the web → `isPro` → `addFirstWeekAndFinish()`
   (inserts the previewed sessions, which the server now allows) → Résumé.
4. **Sheet dismissed** → `finish()` without inserting → Résumé on the Free tier. The week is not
   kept. A teaser that brings it back is a follow-up, not part of this plan.
5. No haptic on blur (feedback memory: only notches under the finger).

**Tests:** store tests for Free + ready → `.paywall`, Pro + ready → insert path, purchase success
→ insert then finish, dismissal → finish without insert. UI check in the simulator with the local
StoreKit config: buy with the intro offer, cancel, restore.

## Step 6 — E2E and release

- Simulator, end to end against the local API (`Xcode` transactions are accepted outside
  production, ADR-044): new account → preview → buy → week in the plan; new account → preview →
  close → Free Résumé, coach shows the teaser, activities visible.
- TestFlight sandbox: the intro offer appears once per sandbox Apple ID, and a second purchase on
  the same ID shows the full price.
- App Review notes: say that the coach is subscription-only, that data stays free, and give a
  demo account with a `manual` entitlement.

## Order and commits

1. Step 1 (config) and step 2 (server), committed per gate, pushed alone after the beta
   entitlements are granted.
2. Step 3 (iOS upsell). It can go to TestFlight right away.
3. Step 4 (pre-account wizard), then step 5 (paywall), one commit each.
4. Step 6, then the docs: the « Pro gating » paragraph of `SHARPIT-APP/CLAUDE.md` (it still says
   Pro gates only analyses and computed metrics), `Features/Onboarding/CLAUDE.md` and
   `Features/Pro/CLAUDE.md`, an iOS ADR (`docs/adr/0020`) for the pre-account wizard draft, and
   ADR-097 marked Accepted.

## Open points

- Does the web keep a separate onboarding? If so, it needs the same reorder or a redirect to the
  app. Not covered here.
- Win-back offer for athletes who closed the paywall (App Store win-back offers): follow-up.
- Bringing the blurred week back on Résumé after a dismissal: follow-up.

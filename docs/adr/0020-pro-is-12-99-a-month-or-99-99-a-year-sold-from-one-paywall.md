# 20. Pro is 12,99 € a month or 99,99 € a year, sold from one paywall

Date: 2026-10-20

## Status

Accepted

## Context

SHARPIT-WEBAPP ADR-097 made every AI coaching surface Pro-only, with a 50 % first-month
introductory offer on the monthly plan and the paywall shown on the onboarding's first week.
It set neither the prices nor what the paywall looks like.

The products were 9,99 € a month and 99,99 € a year. That puts the yearly plan only 17 % below
twelve monthly payments, so it gives little reason to commit. The paywall
(`SharpitProPaywallSheet`) also had problems:

- Its prices were hard-coded (« 99,99 € », « Soit 8,33 € », « −17 % »), so they were wrong in any
  other storefront and after any price change.
- It never showed the introductory offer, which App Review 3.1.2 requires to be shown with the
  price that follows it.
- Five perks had a sentence each, under three section headings.
- A selection haptic fired on every plan change, which the root `CLAUDE.md` forbids.

`ProView` sold through `SubscriptionStoreView` instead, so the app had two paywalls that looked
different.

The cost of an athlete, priced on the Vercel AI Gateway on 2026-10-20 at about 90 % input tokens
and no cache:

| Athlete | Monthly cost |
|---|---|
| Free | one preview week, at most 50 000 tokens ≈ 0,04 $ **once**, then infrastructure only |
| Pro, realistic (a few questions a day + background work) | 0,2–1,5 € |
| Pro at the 500 000-token daily ceiling every day | ≈ 2 $ on `deepseek-v4-flash` (chat), ≈ 11 $ on `gemini-3-flash` (plan/adapt), ≈ 21 $ if the gateway fails over to `claude-haiku-4.5` |

After 20 % French VAT and Apple's 15 % (Small Business Program), the athlete's payment leaves:

- 9,20 € on a 12,99 € month;
- 70,83 € on a 99,99 € year, i.e. 5,90 € a month.

The fixed costs (Vercel Pro, Neon, Apple Developer, Sentry) are estimated at 50–80 € a month.

## Decision

1. **Prices.** We sell `app.sharpit.pro.monthly` at **12,99 €**, with a pay-as-you-go
   introductory offer of **one month at 6,49 €** (−50 %). We sell `app.sharpit.pro.yearly` at
   **99,99 €**, which is about 35 % below twelve monthly payments, with no introductory offer.
   `Config/SharpitPro.storekit` mirrors these prices. App Store Connect is set by hand.
2. **One paywall.** `SharpitProPaywallSheet` is the only place the app sells Pro.
   - The onboarding's first week opens it, passing the coach's week, with the wizard blurred
     behind it.
   - `SharpitProTeaser`, Santé's unlock and `ProView`'s « Passer à Pro » open it as a sheet.
   - `ProView` keeps the status, restore and « Gérer mon abonnement ».
   - `SubscriptionStoreView` is no longer used.
3. **Show, don't explain.**
   - The sheet opens on `ProWeekHero`: a week of sport tiles on the ink band. The onboarding
     shows the athlete's own week. Elsewhere an example week moves one session a day later, once,
     to show the plan adapting.
   - Then a title, three lines of about four words, and the two plans.
   - The selection ring travels between the two plans (`matchedGeometryEffect`) on
     `SharpitMotion.selection`, and the button's label changes with it (`numericText`).
   - There is no haptic.
   - Everything else uses the shared reveal and its stagger, so Reduce Motion is honoured.
4. **Every amount comes from the App Store.** Prices come from `Product.displayPrice` and
   `priceFormatStyle`. `ProPriceReadout` only derives the « −X % » badges, rounded down so the
   sheet never promises more than the App Store charges.
   - The intro offer shows only when `isEligibleForIntroOffer` says this Apple Account can still
     take it. While it is eligible the monthly plan is preselected, otherwise the yearly one.
   - Buying waits for `appAccountToken`, as before.

## Options considered

### Option A — Keep 9,99 € / 99,99 €

**Pros**
- No change in App Store Connect.
- The cheapest entry price.

**Cons**
- The yearly plan saves only 17 %, so most athletes would stay monthly and churn monthly.
- Half price on 9,99 € is 4,99 €, which anchors the coach as a cheap app next to the training-plan
  apps it competes with.

### Option B — 14,99 € / 99,99 €

**Pros**
- 10,62 € net per month.
- A 44 % yearly saving, the strongest push toward the yearly plan.

**Cons**
- The monthly price is above what the athlete wanted to ask while the coach is new and unproven
  on the App Store.

### Option C — 12,99 € / 99,99 € with half price on the first month (chosen)

**Pros**
- A softer monthly price that still makes the yearly plan worth taking (−35 %).
- The first month at 6,49 € lowers the first payment without giving the coach away.
- Even at a ~1 € AI cost, each subscriber leaves 5–8 € a month.

**Cons**
- 1,62 € a month less than option B on every monthly subscriber.

### Option D — A free trial instead of the discount

Rejected by ADR-097. It gives the full coach away for a week to athletes who may never pay. The
preview week already shows the value before the price.

### Paywall: keep `SubscriptionStoreView`

**Pros**
- Apple keeps its legal lines and intro-offer wording correct.

**Cons**
- It cannot show the athlete's week or the motion above.
- It sits beside a second, custom paywall in the onboarding.
- Its picker reads as a system list, not as SharpIt.

The custom sheet keeps the legal parts App Review checks: price, period, renewal line, restore,
terms and privacy.

## Consequences

### Positive

- One paywall to test and keep compliant. Prices and the intro offer stay right in every
  storefront and after any price change in App Store Connect, with no app release.
- Break-even on fixed costs: with 60 % yearly subscribers at about 1 € AI cost each, every
  subscriber leaves about 6,2 € a month, so about **13 Pro subscribers** cover 80 € of fixed costs.
  1 000 Free athletes add roughly 0,05 € each in infrastructure, which about 8 more subscribers
  cover.
- The onboarding shows the athlete's own week behind and inside the paywall, at the moment of
  highest intent.

### Negative

- The Pro ceiling is counted in tokens, not money. On the Haiku failover, an athlete at the
  ceiling every day costs about 21 $ a month, which is more than a yearly subscriber pays. The
  analysis, briefing and autoplan ledgers are outside that ceiling.
- The custom sheet must be checked against App Review 3.1.2 on each change, since Apple's view no
  longer does it.
- Existing TestFlight sandbox subscribers keep the old price until they resubscribe.

### Neutral

- `docs/app-store-submission.md` and `Features/Pro/CLAUDE.md` now name the real product ids
  (`app.sharpit.pro.*`). The 2026-10-19 plan had written `app.sharpit.ios.pro.*`.
- App Store Connect must be changed by hand: the monthly price to 12,99 € and its introductory
  offer to one month at 6,49 €.

## References

- SHARPIT-WEBAPP ADR-097 — Free is the athlete's data; coaching is Pro-only
- SHARPIT-WEBAPP ADR-077 — token budgets (500 000 Pro per rolling 24 h)
- SHARPIT-WEBAPP ADR-044 — SharpIt Pro billing
- Follow-up: a cost-based Pro ceiling (dollars per day from `AiUsageEvent.model` × gateway
  price) instead of a token count, as a SHARPIT-WEBAPP ADR
- App Review Guidelines 3.1.2 (auto-renewable subscriptions)

# SharpIt Pro

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**SharpIt Pro.** StoreKit 2, verified by the web (SHARPIT ADR-044). `ProStore` reads
`/api/v1/pro` (tier, the web's perks, the subscription), carries the web's `appAccountToken` on
every purchase, and hands every transaction — a purchase in `SharpitProPaywallSheet`,
`Transaction.unfinished` and `Transaction.updates` from launch, a restore — to
`/api/v1/billing/apple/verify`, finishing it only once the web has it. The app never decides the
tier. Products: `app.sharpit.pro.monthly` (12,99 €, first month −50 %) and `.yearly` (99,99 €) (`SharpitProProduct`), mirrored in
`Config/SharpitPro.storekit` for the simulator (preselected in the shared scheme's Run →
Options → StoreKit Configuration; `ProProductsTests` keeps the ids in sync). Those local
transactions are environment `Xcode`, unsigned by Apple: only a dev API (`next dev`) accepts
them, so run Debug against the local API (no `SHARPIT_API_ORIGIN` override in `Local.xcconfig`) to buy end to end.

**The paywall.** `SharpitProPaywallSheet` is the only one: the onboarding's first week (drawn in
`ProWeekHero`, the wizard blurred behind), every `SharpitProTeaser`, Santé's unlock and `ProView`'s
« Passer à Pro » open it as a sheet. It shows the week as a picture, the web's Pro perks (`ProPerkGroup`) and the two
plans; every amount is the App Store's `Product` (`ProPriceReadout` only derives the per-month and
the −X %, rounded down). The monthly's intro offer shows only when `isEligibleForIntroOffer` says
the Apple Account can still take it, and is then preselected; otherwise the yearly is. Buying
waits for `appAccountToken`. No haptic on choosing a plan (root rule: notches only).

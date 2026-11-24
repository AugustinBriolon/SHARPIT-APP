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

**Clinique.** The paywall follows its mock-up (`docs/adr/0035`): « SharpIt Pro » as a pill, the
promise as the title, that the data stays free, four lines (coach, self-repairing plan, nutrition
reading, biological age and weekly review) with a glyph in a data hue, the two plans as bordered cards
with a radio mark and the saving as a pill, « Passer à Pro ». The onboarding's week (`ProWeekHero`)
shows only when the paywall is opened with one. `SharpitScreenDemo pro` shows it without offers: the
simulator has no App Store.

**Hors Pro.** `SharpitProTeaser` is Clinique's « hors Pro » card everywhere it stands: the
feature's name over the Pro pill, what it does in a sentence, « Essayer Pro » in ink, a border in the
coach's tone. It states no price: only the paywall quotes the App Store's.

**Everything Pro adds, in a loop (`docs/adr/0039`, the athlete's request, 2026-11-24).** This replaces
the four lines and the sub-paragraph described above. Under the title the paywall shows the eleven
perks (`ProPerkLine.all`, the server's ids, a glyph in a pillar's hue and one sentence each) as a
column rising without end in a window of four and a half lines (`ProPerkConveyor`); a finger moves it
either way and it carries on. Plain list under Reduce Motion, at the accessibility sizes and for
VoiceOver. No haptic. The paywall does not use `ProPerkGroup`: Réglages › Pro does.

# SharpIt Pro

Feature notes, loaded when working in this directory. Repo-wide rules live in the root `CLAUDE.md`.

**SharpIt Pro.** StoreKit 2, verified by the web (SHARPIT ADR-044). `ProStore` reads
`/api/v1/pro` (tier, the web's perks, the subscription), carries the web's `appAccountToken` on
every purchase, and hands every transaction — a purchase in `ProView`'s `SubscriptionStoreView`,
`Transaction.unfinished` and `Transaction.updates` from launch, a restore — to
`/api/v1/billing/apple/verify`, finishing it only once the web has it. The app never decides the
tier. Products: `app.sharpit.ios.pro.monthly` and `.yearly` (`SharpitProProduct`), mirrored in
`Config/SharpitPro.storekit` for the simulator (preselected in the shared scheme's Run →
Options → StoreKit Configuration; `ProProductsTests` keeps the ids in sync). Those local
transactions are environment `Xcode`, unsigned by Apple: only a dev API (`next dev`) accepts
them, so run Debug against the local API (no `SHARPIT_API_ORIGIN` override in `Local.xcconfig`) to buy end to end.

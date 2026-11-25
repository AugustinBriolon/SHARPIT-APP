import Foundation
import Testing
@testable import Sharpit

private let renews = Date(timeIntervalSince1970: 1_798_000_000)

@Test func theStatusNamesThePlanThisIPhoneBought() {
    let active = V1ProSubscription(status: "active", source: "apple", renewsAt: renews, willRenew: true)
    let yearly = ProAppleDetail(plan: .yearly, gracePeriodEndsAt: nil, transactionID: 1)
    let line = ProReadout.status(active, isPro: true, detail: yearly)
    #expect(line.hasPrefix("Annuel · Renouvellement le "))
    #expect(ProReadout.status(active, isPro: true, detail: ProAppleDetail(plan: .monthly, transactionID: 1)).hasPrefix("Mensuel · "))
    // Bought elsewhere or not read yet: the status alone.
    #expect(ProReadout.status(active, isPro: true, detail: nil).hasPrefix("Renouvellement le "))
    // Offered access has no plan to name.
    #expect(ProReadout.status(nil, isPro: true, detail: yearly) == "Accès Pro offert")
}

@Test func aGracePeriodSaysUntilWhenAccessIsKept() {
    let grace = V1ProSubscription(status: "grace_period", source: "apple")
    let line = ProReadout.status(grace, isPro: true, detail: ProAppleDetail(plan: .monthly, gracePeriodEndsAt: renews, transactionID: 1))
    #expect(line.hasPrefix("Mensuel · Paiement en attente. L'accès est maintenu jusqu'au "))
    #expect(ProReadout.status(grace, isPro: true) == "Paiement en attente. L'accès est maintenu")
}

@Test func aProductIsReadAsItsPlan() {
    #expect(SharpitProProduct.Plan(productID: "app.sharpit.pro.monthly") == .monthly)
    #expect(SharpitProProduct.Plan(productID: "app.sharpit.pro.yearly") == .yearly)
    #expect(SharpitProProduct.Plan(productID: "other") == nil)
}

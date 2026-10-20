import Foundation
import Testing
@testable import Sharpit

struct ProPriceReadoutTests {
    @Test func theFirstMonthAtHalfPriceReadsMinusFiftyPercent() {
        #expect(ProPriceReadout.percentOff(full: Decimal(string: "12.99")!, paid: Decimal(string: "6.49")!) == 50)
    }

    @Test func theYearlySavingIsAgainstTwelveMonthlyPayments() {
        #expect(ProPriceReadout.yearlySaving(monthly: Decimal(string: "12.99")!, yearly: Decimal(string: "99.99")!) == 35)
    }

    /// Rounded down: the paywall never promises more than the App Store charges.
    @Test func aSavingIsRoundedDown() {
        #expect(ProPriceReadout.percentOff(full: 10, paid: Decimal(string: "6.01")!) == 39)
    }

    @Test func noBadgeWhenThePriceIsNotLower() {
        #expect(ProPriceReadout.percentOff(full: 10, paid: 10) == nil)
        #expect(ProPriceReadout.percentOff(full: 10, paid: 12) == nil)
        #expect(ProPriceReadout.percentOff(full: 0, paid: 0) == nil)
        #expect(ProPriceReadout.percentOff(full: 100, paid: Decimal(string: "99.5")!) == nil)
    }

    /// The local StoreKit config sells what the paywall is built for: a monthly plan with a
    /// one-month intro offer, and a yearly one without.
    @Test func theLocalStoreKitConfigCarriesTheFirstMonthOffer() throws {
        let config = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Config/SharpitPro.storekit")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        let groups = try #require(json["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }
        let monthly = try #require(subscriptions.first { $0["productID"] as? String == SharpitProProduct.monthly })
        let offer = try #require(monthly["introductoryOffer"] as? [String: Any])
        let price = try #require(Decimal(string: monthly["displayPrice"] as? String ?? ""))
        let offerPrice = try #require(Decimal(string: offer["displayPrice"] as? String ?? ""))

        #expect(offer["subscriptionPeriod"] as? String == "P1M")
        #expect(offer["numberOfPeriods"] as? Int == 1)
        #expect(ProPriceReadout.percentOff(full: price, paid: offerPrice) == 50)
    }
}

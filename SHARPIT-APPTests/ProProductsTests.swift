import Foundation
import Testing
@testable import Sharpit

struct ProProductsTests {
    /// The simulator buys from `Config/SharpitPro.storekit`; App Store Connect must carry the same
    /// identifiers. This keeps the local config and `SharpitProProduct` from drifting apart.
    @Test func storeKitConfigurationSellsExactlyTheProProducts() throws {
        let config = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Config/SharpitPro.storekit")
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        let groups = try #require(json["subscriptionGroups"] as? [[String: Any]])
        let subscriptions = groups.flatMap { $0["subscriptions"] as? [[String: Any]] ?? [] }

        #expect(groups.count == 1)
        #expect(Set(subscriptions.compactMap { $0["productID"] as? String }) == Set(SharpitProProduct.all))
    }
}

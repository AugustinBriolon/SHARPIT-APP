import Foundation
import Testing
@testable import Sharpit

@Suite struct AppleCalendarSourceTests {
    @Test @MainActor func syncLinkedFromServerUpdatesToggle() async throws {
        let suite = "apple-calendar-resync"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        final class OKLink: AppleCalendarLinking, @unchecked Sendable {
            func linkAppleCalendar(_ linked: Bool, token: String) async throws {}
        }

        let source = AppleCalendarSource(client: OKLink(), defaults: defaults)
        source.bind(userId: "u1")
        source.syncLinkedFromServer(true)
        #expect(source.isLinked)
        source.syncLinkedFromServer(false)
        #expect(!source.isLinked)
    }
}

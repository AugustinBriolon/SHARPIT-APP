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

    @Test @MainActor func disableFailureKeepsLinked() async throws {
        let suite = "apple-calendar-disable-fail"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        final class FailingUnlink: AppleCalendarLinking, @unchecked Sendable {
            func linkAppleCalendar(_ linked: Bool, token: String) async throws {
                if !linked { throw URLError(.notConnectedToInternet) }
            }
        }

        let source = AppleCalendarSource(client: FailingUnlink(), defaults: defaults)
        source.bind(userId: "u1")
        source.syncLinkedFromServer(true)
        await source.disable(token: { "tok" })
        #expect(source.isLinked)
        #expect(source.state == .failed("Déconnexion Calendrier Apple impossible."))
    }

    @Test @MainActor func disableShowsOffOnTheTap() async throws {
        let suite = "apple-calendar-disable-at-once"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        final class WatchingLink: AppleCalendarLinking, @unchecked Sendable {
            var during: (@Sendable () async -> Void)?
            func linkAppleCalendar(_ linked: Bool, token: String) async throws { await during?() }
        }
        @MainActor final class Seen { var linked: Bool? }

        let client = WatchingLink()
        let source = AppleCalendarSource(client: client, defaults: defaults)
        source.bind(userId: "u1")
        source.syncLinkedFromServer(true)
        let seen = Seen()
        client.during = { await MainActor.run { seen.linked = source.isLinked } }
        await source.disable(token: { "tok" })
        #expect(seen.linked == false)
        #expect(!source.isLinked)
        #expect(source.state == .idle)
    }

    @Test @MainActor func linkBumpsRevisionOnlyWhenTheServerTookIt() async throws {
        let suite = "apple-calendar-link-revision"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)

        final class FlakyLink: AppleCalendarLinking, @unchecked Sendable {
            var fails = false
            func linkAppleCalendar(_ linked: Bool, token: String) async throws {
                if fails { throw URLError(.badServerResponse) }
            }
        }
        let client = FlakyLink()
        let sync = AppleCalendarSync(defaults: defaults, accessRequest: { true })
        let source = AppleCalendarSource(sync: sync, client: client, defaults: defaults)
        source.bind(userId: "u1")

        await source.enable(token: { "tok" })
        #expect(source.linkRevision == 1)

        client.fails = true
        await source.enable(token: { "tok" })
        #expect(source.linkRevision == 1)
    }
}

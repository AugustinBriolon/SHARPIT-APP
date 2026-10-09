import Foundation
import Testing
@testable import Sharpit

@Suite struct AppleCalendarPullTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func date(_ text: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = calendar.timeZone
        return formatter.date(from: text)!
    }

    @Test func calendarMoveWinsOverPlanStart() {
        let planStart = date("2026-10-10T07:00:00+0200")
        let eventStart = date("2026-10-10T18:00:00+0200")
        let resolved = AppleCalendarPull.resolveStart(plan: planStart, event: eventStart)
        #expect(resolved == eventStart)
    }

    @Test func planStartStaysWhenNoEvent() {
        let planStart = date("2026-10-10T07:00:00+0200")
        #expect(AppleCalendarPull.resolveStart(plan: planStart, event: nil) == planStart)
    }

    @Test @MainActor func legacyPlanCalendarSyncMigratesToLink() async throws {
        let suite = "legacy-calendar-migrate"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: AppleCalendarSync.enabledKey)
        defaults.set("legacy-cal-id", forKey: "planCalendarSync.calendarId")

        final class LinkSpy: AppleCalendarLinking, @unchecked Sendable {
            private(set) var linked: [Bool] = []
            func linkAppleCalendar(_ linked: Bool, token: String) async throws {
                self.linked.append(linked)
            }
        }
        let spy = LinkSpy()
        let sync = AppleCalendarSync(defaults: defaults)
        let migrated = await sync.migrateLegacyPlanCalendarSync(calendarLinker: spy, token: "t")
        #expect(migrated)
        #expect(spy.linked == [true])
        #expect(defaults.string(forKey: "appleCalendar.writeCalendarId") == "legacy-cal-id")
        #expect(!defaults.bool(forKey: AppleCalendarSync.enabledKey))
        #expect(await sync.migrateLegacyPlanCalendarSync(calendarLinker: spy, token: "t") == false)
    }

    @Test @MainActor func legacyMigrationRetriesWhenLinkFails() async throws {
        let suite = "legacy-calendar-link-fail"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: AppleCalendarSync.enabledKey)

        final class FailingLink: AppleCalendarLinking, @unchecked Sendable {
            func linkAppleCalendar(_ linked: Bool, token: String) async throws {
                throw URLError(.notConnectedToInternet)
            }
        }
        let sync = AppleCalendarSync(defaults: defaults)
        #expect(await sync.migrateLegacyPlanCalendarSync(calendarLinker: FailingLink(), token: "t") == false)
        #expect(defaults.bool(forKey: AppleCalendarSync.enabledKey))
        #expect(!defaults.bool(forKey: AppleCalendarSync.legacyMigrationDoneKey))
    }

    @Test func writeRunsOnlyWhenAppleCalendarIsPrimary() {
        let connected = ["google", "apple-calendar"]
        let primaryApple = V1SourcePrefs(classes: [
            "calendar": V1ClassSources(primary: "apple-calendar", enabled: ["google", "apple-calendar"]),
        ])
        let primaryGoogle = V1SourcePrefs(classes: [
            "calendar": V1ClassSources(primary: "google", enabled: ["google", "apple-calendar"]),
        ])
        #expect(AppleCalendarSync.shouldWrite(prefs: primaryApple, connected: connected))
        #expect(!AppleCalendarSync.shouldWrite(prefs: primaryGoogle, connected: connected))
    }

    @Test func busyUploadRunsWhenAppleCalendarEnabledNotOnlyWhenPrimary() {
        let connected = ["google", "apple-calendar"]
        let primaryGoogle = V1SourcePrefs(classes: [
            "calendar": V1ClassSources(primary: "google", enabled: ["google", "apple-calendar"]),
        ])
        #expect(!AppleCalendarSync.shouldWrite(prefs: primaryGoogle, connected: connected))
        #expect(AppleCalendarSync.shouldUploadBusy(prefs: primaryGoogle, connected: connected))
        #expect(!AppleCalendarSync.shouldUploadBusy(
            prefs: V1SourcePrefs(classes: [
                "calendar": V1ClassSources(primary: "google", enabled: ["google"]),
            ]),
            connected: connected
        ))
    }

    @Test func sharpitSessionURLParsesSessionId() {
        let url = PlanCalendarPlanner.url(for: "abc-42")
        #expect(AppleCalendarPull.sessionId(fromSharpitURL: url) == "abc-42")
        #expect(AppleCalendarPull.sessionId(fromSharpitURL: URL(string: "https://sharpit.app")!) == nil)
    }

    @Test func calendarDeleteClearsWhenPreviouslyWritten() {
        #expect(AppleCalendarPull.shouldClearScheduleAfterCalendarDelete(wasOnWriteCalendar: true, wasSyncedBefore: false))
        #expect(AppleCalendarPull.shouldClearScheduleAfterCalendarDelete(wasOnWriteCalendar: false, wasSyncedBefore: true))
        #expect(!AppleCalendarPull.shouldClearScheduleAfterCalendarDelete(wasOnWriteCalendar: false, wasSyncedBefore: false))
    }

    @Test func calendarDeletePatchClearsStartTime() {
        let fields = AppleCalendarPull.clearScheduleFields()
        #expect(fields["startTime"] == .null)
    }

    @Test func skipApplyPreservesEventKitRowFromStaleDeletion() {
        let url = PlanCalendarPlanner.url(for: "sess-1")
        let preserve: Set<String> = ["sess-1"]
        #expect(AppleCalendarPull.retainEventDuringSkipApply(url: url, preserveSessionIds: preserve))
        #expect(!AppleCalendarPull.retainEventDuringSkipApply(url: url, preserveSessionIds: []))
        #expect(!AppleCalendarPull.retainEventDuringSkipApply(
            url: URL(string: "https://example.com")!,
            preserveSessionIds: preserve
        ))
    }

    @Test func clearedUnlinkTombstoneBlocksAllDayRecreateUntilReschedule() {
        #expect(!AppleCalendarPull.shouldWriteSessionToCalendar(sessionId: "s1", clearedAfterUnlinkIds: ["s1"]))
        #expect(AppleCalendarPull.shouldWriteSessionToCalendar(sessionId: "s2", clearedAfterUnlinkIds: ["s1"]))
        let untimed = V1PlannedSessionItem(id: "s1", date: Date(), title: "Run", type: "RUN")
        let timed = V1PlannedSessionItem(id: "s1", date: Date(), startTime: "09:00", title: "Run", type: "RUN")
        let active = AppleCalendarPull.clearedAfterUnlinkIds(stored: ["s1"], sessions: [untimed])
        #expect(active == ["s1"])
        #expect(AppleCalendarPull.clearedAfterUnlinkIds(stored: ["s1"], sessions: [timed]).isEmpty)
    }
}

@Suite struct PlanCalendarPlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func day(_ text: String) -> Date {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    @Test func aTimedSessionTakesItsSlot() throws {
        let session = V1PlannedSessionItem(
            id: "s1", date: day("2026-10-06"), startTime: "18:30", title: "Seuil", type: "RUN", durationMin: 55
        )
        let event = try #require(PlanCalendarPlanner.events(for: [session], calendar: calendar).first)
        #expect(!event.isAllDay)
        #expect(calendar.component(.hour, from: event.start) == 18)
        #expect(event.end.timeIntervalSince(event.start) == 55 * 60)
        #expect(event.url.absoluteString == "sharpit://plan/session/s1")
        #expect(event.title == "Seuil")
    }

    @Test func anUntimedSessionIsAllDay() throws {
        let session = V1PlannedSessionItem(id: "s2", date: day("2026-10-07"), title: "Footing", type: "RUN")
        let event = try #require(PlanCalendarPlanner.events(for: [session], calendar: calendar).first)
        #expect(event.isAllDay)
        #expect(event.end.timeIntervalSince(event.start) == 86_400)
        #expect(event.notes == nil)
    }
}

@Suite struct DaySwipeTests {
    @Test func theLeftEdgeStaysBack() {
        #expect(DaySwipe.step(startX: 10, translation: CGSize(width: 200, height: 0)) == nil)
    }

    @Test func theMiddleTurnsTheDay() {
        #expect(DaySwipe.step(startX: 180, translation: CGSize(width: 120, height: 10)) == .previous)
        #expect(DaySwipe.step(startX: 180, translation: CGSize(width: -120, height: 10)) == .next)
    }

    @Test func aShortOrMostlyVerticalSwipeScrolls() {
        #expect(DaySwipe.step(startX: 180, translation: CGSize(width: 40, height: 0)) == nil)
        #expect(DaySwipe.step(startX: 180, translation: CGSize(width: 90, height: 80)) == nil)
    }

    @Test func neverPastToday() {
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(DaySwipe.day(after: .next, from: today, today: today) == nil)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        #expect(DaySwipe.day(after: .next, from: yesterday, today: today) != nil)
        #expect(DaySwipe.day(after: .previous, from: today, today: today) == yesterday)
    }

    @Test func aFlickTurnsTheDayOnlyTheWayItWasThrown() {
        let short = CGSize(width: -30, height: 2)
        #expect(DaySwipe.step(startX: 180, translation: short, predictedEnd: CGSize(width: -260, height: 0)) == .next)
        #expect(DaySwipe.step(startX: 180, translation: short, predictedEnd: CGSize(width: 260, height: 0)) == nil)
        #expect(DaySwipe.step(startX: 180, translation: short, predictedEnd: CGSize(width: -80, height: 0)) == nil)
    }

    @Test func thePageFollowsTheFingerAndHoldsBackWhereNoDayLies() {
        #expect(DaySwipe.offset(for: -120, canTurn: true, width: 390) == -120)
        let held = DaySwipe.offset(for: -120, canTurn: false, width: 390)
        #expect(held < 0 && held > -120)
        #expect(DaySwipe.offset(for: -2000, canTurn: false, width: 390) > -390)
    }

    @Test func aVerticalOrEdgeDragIsNotATurn() {
        #expect(DaySwipe.axis(startX: 180, translation: CGSize(width: 30, height: 40)) == .vertical)
        #expect(DaySwipe.axis(startX: 10, translation: CGSize(width: 80, height: 0)) == .vertical)
        #expect(DaySwipe.axis(startX: 180, translation: CGSize(width: 80, height: 10)) == .horizontal)
    }

    @Test func aTurnIsDecidedOnceTheFingerHasTravelled() {
        #expect(DaySwipe.isTurn(startX: 180, translation: CGSize(width: 6, height: 0)) == nil)
        #expect(DaySwipe.isTurn(startX: 180, translation: CGSize(width: 12, height: 4)) == true)
        #expect(DaySwipe.isTurn(startX: 180, translation: CGSize(width: 12, height: 20)) == false)
        #expect(DaySwipe.isTurn(startX: 10, translation: CGSize(width: 40, height: 0)) == false)
    }

    @Test func aReleasedDragCoastsTheWayItWasThrown() {
        let still = DaySwipe.projected(CGSize(width: -30, height: 2), velocity: CGSize(width: 0, height: 0))
        #expect(still == CGSize(width: -30, height: 2))
        let thrown = DaySwipe.projected(CGSize(width: -30, height: 0), velocity: CGSize(width: -1000, height: 0))
        #expect(thrown.width < -400 && thrown.width > -600)
    }

    @Test func aPickedDayComesInFromItsSideOfTime() {
        let today = Date(timeIntervalSince1970: 1_790_000_000)
        let lastWeek = Calendar.current.date(byAdding: .day, value: -7, to: today)!
        #expect(DaySwipe.step(from: today, to: lastWeek) == .previous)
        #expect(DaySwipe.step(from: lastWeek, to: today) == .next)
        #expect(DaySwipe.step(from: today, to: today) == nil)
        #expect(DaySwipe.entrySign(.next) > 0)
        #expect(DaySwipe.entrySign(.previous) < 0)
    }
}

@Suite struct JournalDrivingTests {
    @Test func wordsTheMinutesLikeTheWeb() {
        #expect(JournalDrivingFormat.minutes(nil) == "— min")
        #expect(JournalDrivingFormat.minutes(45) == "45 min")
        #expect(JournalDrivingFormat.minutes(90) == "1 h 30")
        #expect(JournalDrivingFormat.minutes(120) == "2 h")
    }

    @Test func theMinutesTravelWithTheDay() throws {
        let entry = try JSONDecoder().decode(
            V1DayJournalEntry.self,
            from: Data(#"{ "trainingDayId": "2026-10-05", "factors": {}, "drivingMinutes": 75 }"#.utf8)
        )
        #expect(entry.drivingMinutes == 75)
        #expect(entry.hasAnyAnswer)
        let encoded = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        #expect(encoded.contains("\"drivingMinutes\":75"))
    }
}

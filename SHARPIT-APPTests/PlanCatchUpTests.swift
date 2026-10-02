import Foundation
import Testing
@testable import Sharpit

private let calendar = Calendar(identifier: .gregorian)
private let now = Date(timeIntervalSince1970: 1_789_000_000)

private func daysAgo(_ days: Int) -> Date {
    calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
}

private func missed(_ title: String?, daysAgo days: Int) -> PlanEntry {
    .missed(V1PlannedSessionItem(id: "s-\(days)", date: daysAgo(days), title: title, type: "RUN"))
}

@MainActor @Test func aSessionMissedThisWeekOffersToCatchUp() throws {
    let offer = try #require(PlanCatchUp.offer(for: missed("Seuil 3×10", daysAgo: 2), now: now, calendar: calendar))
    #expect(offer.label == "Seuil 3×10")
}

@MainActor @Test func anOldMissOrOneStillAheadOffersNothing() {
    #expect(PlanCatchUp.offer(for: missed("Seuil", daysAgo: 8), now: now, calendar: calendar) == nil)
    #expect(PlanCatchUp.offer(for: missed("Seuil", daysAgo: 0), now: now, calendar: calendar) == nil)
    let planned = PlanEntry.planned(V1PlannedSessionItem(id: "p", date: daysAgo(1), title: "Seuil", type: "RUN"))
    #expect(PlanCatchUp.offer(for: planned, now: now, calendar: calendar) == nil)
}

@MainActor @Test func theCoachIsToldWhatWasMissedAndWhatIsAsked() throws {
    let offer = try #require(PlanCatchUp.offer(for: missed("Seuil 3×10", daysAgo: 1), now: now, calendar: calendar))
    let focus = offer.focus(now: now, calendar: calendar)

    #expect(focus.hasPrefix("J'ai raté « Seuil 3×10 » hier."))
    #expect(focus.contains("sans surcharge"))
}

@MainActor @Test func anUntitledMissIsNamedByItsSport() throws {
    let offer = try #require(PlanCatchUp.offer(for: missed(nil, daysAgo: 3), now: now, calendar: calendar))
    #expect(!offer.label.isEmpty)
}

import CoreSpotlight
import Foundation
import Testing
@testable import Sharpit

private func planned(_ id: String, title: String?, type: String?) throws -> V1PlannedSessionItem {
    let title = title.map { "\"\($0)\"" } ?? "null"
    let type = type.map { "\"\($0)\"" } ?? "null"
    let json = #"{"id":"\#(id)","date":"2026-12-03T11:00:00.000Z","title":\#(title),"type":\#(type)}"#
    return try JSONDecoder().decode(V1PlannedSessionItem.self, from: Data(json.utf8))
}

@Test func aPlannedSessionIsFoundByItsTitleAndOpensItsPage() throws {
    let entry = SpotlightEntry.plannedSession(try planned("ps-1", title: "Seuil 40 min", type: "RUN"))
    #expect(entry.title == "Seuil 40 min")
    #expect(entry.detail == "\(V1ActivityType.run.label) · Séance prévue")
    #expect(entry.uniqueIdentifier == "https://sharpit.app/plan/session/ps-1")
    #expect(IncomingLink.parse(entry.link) == .plannedSession(id: "ps-1"))
    // Without a title, the sport names it.
    #expect(SpotlightEntry.plannedSession(try planned("ps-2", title: nil, type: "BIKE")).title == V1ActivityType.bike.label)
}

@Test func everyKindOpensALinkTheAppReads() throws {
    let goal = V1Goal(id: "g-1", title: "Semi sous 1 h 30", kind: .race, achieved: false)
    let entries = [
        SpotlightEntry.plannedSession(try planned("ps-1", title: "Seuil", type: "RUN")),
        SpotlightEntry.goal(goal),
    ]
    for entry in entries { #expect(IncomingLink.parse(entry.link) != nil, "\(entry.kind)") }
    #expect(IncomingLink.parse(URL(string: "https://sharpit.app/activity/a-1")!) == .activity(id: "a-1"))
}

@Test func aSearchResultTappedOpensTheLinkItWasIndexedUnder() {
    let info: [AnyHashable: Any] = [CSSearchableItemActivityIdentifier: "https://sharpit.app/plan/session/ps-1"]
    #expect(SpotlightLink.url(from: info) == URL(string: "https://sharpit.app/plan/session/ps-1"))
    #expect(SpotlightLink.url(from: nil) == nil)
}

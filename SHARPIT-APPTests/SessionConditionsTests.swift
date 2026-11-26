import Foundation
import Testing
import UIKit
@testable import Sharpit

private func session(_ json: String) throws -> V1PlannedSessionItem {
    try JSONDecoder().decode(V1PlannedSessionItem.self, from: Data(json.utf8))
}

/// The server's `environmentContext`, as `resolvePlannedSessionContext` stores it.
private let hotWetContext = #"""
"environmentContext":{"intention":{"exposure":"OUTDOOR"},"environment":{"thermalStressLevel":"HIGH"},
"advisories":[
  {"kind":"REDUCE_INTENSITY","priority":1,"headlineCode":"h","rationaleCode":"r","confidence":0.8},
  {"kind":"RAIN_RISK","priority":2,"headlineCode":"h","rationaleCode":"r","confidence":0.7},
  {"kind":"PROCEED","priority":10,"headlineCode":"h","rationaleCode":"r","confidence":0.7},
  {"kind":"SOMETHING_NEW","priority":11,"headlineCode":"h","rationaleCode":"r","confidence":0.5}
],"preparation":[]}
"""#

@Test func aPlannedSessionReadsWhatTheForecastAsksInTheServersOrder() throws {
    let item = try session(#"{"id":"s1","date":"2026-11-27T00:00:00.000Z","#  + hotWetContext + "}")
    #expect(item.conditions?.advisories == [.reduceIntensity, .rainRisk])
}

@Test func aSessionTheServerHasNotReadYetHasNoConditions() throws {
    #expect(try session(#"{"id":"s1","date":"2026-11-27T00:00:00.000Z"}"#).conditions == nil)
    #expect(try session(#"{"id":"s1","date":"2026-11-27T00:00:00.000Z","environmentContext":null}"#).conditions == nil)
    // A shape the app does not know never costs the session itself.
    #expect(try session(#"{"id":"s1","date":"2026-11-27T00:00:00.000Z","environmentContext":{"advisories":7}}"#)
        .conditions?.advisories == [])
}

@Test func onlyASessionStillToDoShowsItsForecast() {
    let now = Date(timeIntervalSince1970: 1_795_694_400) // 2026-11-26, noon UTC
    let conditions = V1SessionConditions(advisories: [.hydration])
    let ahead = V1PlannedSessionItem(id: "a", date: now.addingTimeInterval(86_400), conditions: conditions)
    let today = V1PlannedSessionItem(id: "t", date: now, conditions: conditions)
    let past = V1PlannedSessionItem(id: "p", date: now.addingTimeInterval(-86_400), conditions: conditions)
    let done = V1PlannedSessionItem(id: "d", date: now, completed: true, conditions: conditions)

    #expect(PlannedSessionPreview.conditions(of: ahead, now: now) == [.hydration])
    #expect(PlannedSessionPreview.conditions(of: today, now: now) == [.hydration])
    #expect(PlannedSessionPreview.conditions(of: past, now: now).isEmpty)
    #expect(PlannedSessionPreview.conditions(of: done, now: now).isEmpty)
}

@Test func aMovedSessionDropsAForecastWrittenForAnotherDay() {
    let day = Date(timeIntervalSince1970: 1_795_694_400)
    let item = V1PlannedSessionItem(id: "s", date: day, type: "RUN", conditions: V1SessionConditions(advisories: [.rainRisk]))
    var draft = PlannedSessionDraft(session: item)
    #expect(item.applying(draft).conditions == item.conditions)
    draft.day = day.addingTimeInterval(2 * 86_400)
    #expect(item.applying(draft).conditions == nil)
}

@Test func everyAdvisorySaysWhatToDoAndWhy() {
    for advisory in V1SessionAdvisory.allCases {
        #expect(!advisory.headline.isEmpty)
        #expect(!advisory.rationale.isEmpty)
        #expect(UIImage(systemName: advisory.symbolName) != nil, "\(advisory) has no SF Symbol")
    }
}

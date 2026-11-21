import Foundation
import Testing
@testable import Sharpit

/// « Fil de la journée »: a session is drawn done only once it is (SHARPIT ADR-138).
@Test func onlyADoneSessionIsDrawnDone() throws {
    func event(_ json: String) throws -> V1DayTimelineEvent {
        try JSONDecoder().decode(V1DayTimelineEvent.self, from: Data(json.utf8))
    }
    #expect(try event(#"{"kind":"session","minuteOfDay":1080,"title":"Seuil","detail":"Prévue","state":"planned"}"#).isDoneSession == false)
    #expect(try event(#"{"kind":"session","minuteOfDay":430,"title":"Footing","detail":"Faite","state":"done"}"#).isDoneSession)
    // A server before the state still says it in the detail.
    #expect(try event(#"{"kind":"session","minuteOfDay":null,"title":"Footing","detail":"Faite"}"#).isDoneSession)
    #expect(try event(#"{"kind":"session","minuteOfDay":null,"title":"Seuil","detail":"Prévue"}"#).isDoneSession == false)
    #expect(try event(#"{"kind":"meal","minuteOfDay":480,"title":"Petit-déjeuner","detail":null}"#).isDoneSession == false)
}

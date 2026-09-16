import Foundation
import Testing
@testable import Sharpit

@Test func foldKeepsOnlyOvernightGauges() throws {
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    let fold = TodayFoldMapper.map(response)
    let keys = fold.gauges.map(\OvernightGaugeModel.key)
    #expect(keys == [V1TodaySignalKey.sleep, V1TodaySignalKey.recovery])
}

@Test func confidenceBarsMatchWebThresholds() {
    #expect(ConfidenceBars.filled(fromPct: nil) == 0)
    #expect(ConfidenceBars.filled(fromPct: 10) == 1)
    #expect(ConfidenceBars.filled(fromPct: 34) == 2)
    #expect(ConfidenceBars.filled(fromPct: 67) == 3)
}

@Test func packTierBarsTone() {
    #expect(PackTierTone.bars(for: .full) == .highlight)
    #expect(PackTierTone.bars(for: .partial) == .caution)
    #expect(PackTierTone.bars(for: .insufficient) == .muted)
    #expect(PackTierTone.bars(for: nil) == .highlight)
}

@Test func priorityTagOnlyWhenMultipleSessionsCompete() {
    #expect(SessionPriorityPolicy.showsTag(sessionCount: 1, priority: true) == false)
    #expect(SessionPriorityPolicy.showsTag(sessionCount: 2, priority: true) == true)
    #expect(SessionPriorityPolicy.showsTag(sessionCount: 2, priority: false) == false)
}


@Test func foldMapsPlateTrustFields() throws {
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    let fold = TodayFoldMapper.map(response)
    #expect(fold.plate.statusLabel == "FEU VERT")
    #expect(fold.plate.actionLine == "Entraîne-toi — légèrement")
    #expect(fold.plate.packTier == V1TodayPackTier.partial)
    #expect(fold.sessions.first?.sport == "Course")
    #expect(fold.sessions.first?.priority == true)
}

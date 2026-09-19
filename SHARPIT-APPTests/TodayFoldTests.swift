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

@Test func tickDialSweepsTheTopSemicircle() {
    let geometry = SharpitTickGaugeGeometry.self
    let first = geometry.point(angle: geometry.angle(at: 0), radius: geometry.radiusOuter)
    let last = geometry.point(
        angle: geometry.angle(at: geometry.tickCount - 1),
        radius: geometry.radiusOuter
    )

    // Left end, right end, both on the centre line.
    #expect(abs(first.x - (geometry.centreX - geometry.radiusOuter)) < 0.01)
    #expect(abs(first.y - geometry.centreY) < 0.01)
    #expect(abs(last.x - (geometry.centreX + geometry.radiusOuter)) < 0.01)
    #expect(abs(last.y - geometry.centreY) < 0.01)
}

@Test func everyTickStaysOnItsRadius() {
    let geometry = SharpitTickGaugeGeometry.self
    for index in 0..<geometry.tickCount {
        let point = geometry.point(angle: geometry.angle(at: index), radius: geometry.radiusOuter)
        let dx = point.x - geometry.centreX
        let dy = point.y - geometry.centreY
        #expect(abs((dx * dx + dy * dy).squareRoot() - geometry.radiusOuter) < 0.01)
        // The dial is the top half only.
        #expect(point.y <= geometry.centreY + 0.01)
    }
}

@Test func theThumbSitsBetweenTheTickRadii() {
    let geometry = SharpitTickGaugeGeometry.self
    let thumb = geometry.thumb(forScore: 60)
    let dx = thumb.x - geometry.centreX
    let dy = thumb.y - geometry.centreY
    let distance = (dx * dx + dy * dy).squareRoot()

    #expect(distance > geometry.radiusInner)
    #expect(distance < geometry.radiusOuter)
}

@Test func ticksLightUpToTheScoreAndNoFurther() {
    // Mirrors the web's overnightTickStroke: unread dial is all border, a read one lights
    // every tick at or below the score and leaves the rest as track.
    let unread = SharpitTickTone.stroke(at: 10, score: nil)
    #expect(unread == SharpitColor.analysisBorder)

    let geometry = SharpitTickGaugeGeometry.self
    for index in 0..<geometry.tickCount {
        let tickScore = geometry.tickScore(at: index)
        let stroke = SharpitTickTone.stroke(at: index, score: 60)
        if tickScore > 60 {
            #expect(stroke == SharpitColor.analysisBorder)
        } else {
            #expect(stroke != SharpitColor.analysisBorder)
        }
    }
}

@Test func theTicksApproachingTheScoreTakeTheHighlight() {
    let geometry = SharpitTickGaugeGeometry.self
    let justBelow = (0..<geometry.tickCount).filter { index in
        let score = geometry.tickScore(at: index)
        return score <= 60 && score >= 60 - SharpitTickTone.highlightBand
    }

    #expect(!justBelow.isEmpty)
    for index in justBelow {
        #expect(SharpitTickTone.stroke(at: index, score: 60) == SharpitColor.highlight)
    }
}

@Test func progressFractionMapsZeroScore() {
    #expect(AnimatedScoreText.progressFraction(from: "0") == 0)
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

// MARK: - Consistency

@Test func foldCarriesConsistencyFromThePayload() throws {
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    let fold = TodayFoldMapper.map(response)

    let consistency = try #require(fold.consistency)
    #expect(consistency.days.count == 8)
    #expect(consistency.thisWeekSessionCount == 2)
    #expect(consistency.days.filter(\.isToday).count == 1)
}

@Test func consistencyDaysAreUniquelyIdentified() throws {
    let response = try JSONDecoder().decode(V1TodayResponse.self, from: fixtureData("full.json"))
    let consistency = try #require(response.consistency)

    #expect(Set(consistency.days.map(\.id)).count == consistency.days.count)
}

@Test func aPayloadWithoutConsistencyStillDecodes() throws {
    // Snapshots cached before the field existed must not fail to decode — the strip is
    // simply absent for them.
    let data = try fixtureData("full.json")
    var json = try #require(
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    json.removeValue(forKey: "consistency")
    let stripped = try JSONSerialization.data(withJSONObject: json)

    let response = try JSONDecoder().decode(V1TodayResponse.self, from: stripped)
    #expect(response.consistency == nil)
    #expect(TodayFoldMapper.map(response).consistency == nil)
}

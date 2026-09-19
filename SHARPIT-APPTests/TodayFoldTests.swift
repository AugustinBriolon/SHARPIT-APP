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

@Test func overnightArcTipMapsScoreAlongTopSemicircle() {
    let left = OvernightArcMath.tipOffset(progress: 0, radius: 100)
    let top = OvernightArcMath.tipOffset(progress: 0.5, radius: 100)
    let right = OvernightArcMath.tipOffset(progress: 1, radius: 100)
    #expect(abs(left.width + 100) < 0.01)
    #expect(abs(left.height) < 0.01)
    #expect(abs(top.width) < 0.01)
    #expect(abs(top.height + 100) < 0.01)
    #expect(abs(right.width - 100) < 0.01)
    #expect(abs(right.height) < 0.01)
}

@Test func overnightArcTipStaysOnCircleDuringProgress() {
    let radius: CGFloat = 100
    for step in 0...10 {
        let t = CGFloat(step) / 10
        let offset = OvernightArcMath.tipOffset(progress: t, radius: radius)
        let distance = (offset.width * offset.width + offset.height * offset.height).squareRoot()
        #expect(abs(distance - radius) < 0.01)
    }
}

@Test func overnightScoreSitsAtTheMidpointOfTheBowl() {
    // Equal air above the number and below it. A fraction picked any other way leaves
    // the block hugging either the apex or the baseline.
    let radius: CGFloat = 74
    let centre = OvernightGaugeLayout.scoreCentre(radius: radius)

    #expect(centre == radius / 2)
    #expect(abs((radius - centre) - centre) < 0.01)
}

@Test func overnightScoreCentreScalesWithTheRadius() {
    #expect(
        OvernightGaugeLayout.scoreCentre(radius: 148)
            > OvernightGaugeLayout.scoreCentre(radius: 74)
    )
    #expect(OvernightGaugeLayout.scoreCentre(radius: 0) == 0)
}

@Test func overnightBowlClearsTheArcPlusItsApexAir() {
    // height = width / ratio must clear the radius, the stroke's cap and the air above
    // the apex — otherwise the arc overflows the panel, which is what 2.05 did.
    for width in [CGFloat(130), 160, 190] {
        let height = width / OvernightGaugeLayout.bowlAspectRatio
        let radius = width / 2 - OvernightGaugeLayout.arcLineWidth / 2
        let needed = radius + OvernightGaugeLayout.arcLineWidth / 2 + OvernightGaugeLayout.apexAir

        #expect(height >= needed - 1)
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

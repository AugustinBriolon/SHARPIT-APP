import Foundation
import Testing
@testable import Sharpit

@Test func animatedScoreParsesInteger() {
    let parsed = AnimatedScoreText.parse("66")
    #expect(parsed?.value == 66)
    #expect(parsed?.decimals == 0)
}

@Test func animatedScoreParsesDecimalComma() {
    let parsed = AnimatedScoreText.parse("1,8")
    #expect(parsed?.value == 1.8)
    #expect(parsed?.decimals == 1)
}

@Test func animatedScoreProgressForIndex() {
    #expect(AnimatedScoreText.progressFraction(from: "66") == 0.66)
    #expect(AnimatedScoreText.progressFraction(from: "—") == nil)
    #expect(AnimatedScoreText.progressFraction(from: "100") == 1.0)
}

@Test func animatedScoreProgressSkipsSmallEffortScale() {
    #expect(AnimatedScoreText.progressFraction(from: "1,8") == nil)
}

@Test func sharpitMotionStaggerFormula() {
    #expect(SharpitMotion.staggerStep == 0.048)
    let delay = SharpitMotion.staggerDelay(index: 3)
    if SharpitMotion.reduceMotion {
        #expect(delay == 0)
    } else {
        #expect(abs(delay - 3 * SharpitMotion.staggerStep) < 0.000_001)
    }
}

@Test func sharpitMotionStaggerStopsGrowingOnLongLists() {
    let capped = SharpitMotion.staggerDelay(index: SharpitMotion.maxStaggeredItems)
    #expect(SharpitMotion.staggerDelay(index: 30) == capped)
    #expect(SharpitMotion.staggerDelay(index: -2) == 0)
}

@Test func winStoreConsumesOnce() {
    SharpitWinStore.resetForTests()
    let key = SharpitWinStore.arrivalKey(trainingDayId: "2099-01-01")
    #expect(SharpitWinStore.consume(key) == true)
    #expect(SharpitWinStore.consume(key) == false)
    SharpitWinStore.resetForTests()
}

@Test func winStoreTracksConfidence() {
    SharpitWinStore.resetForTests()
    let day = "2099-02-02"
    #expect(SharpitWinStore.lastConfidence(trainingDayId: day) == nil)
    SharpitWinStore.setLastConfidence(70, trainingDayId: day)
    #expect(SharpitWinStore.lastConfidence(trainingDayId: day) == 70)
    SharpitWinStore.setLastConfidence(80, trainingDayId: day)
    #expect(SharpitWinStore.lastConfidence(trainingDayId: day) == 80)
    SharpitWinStore.resetForTests()
}

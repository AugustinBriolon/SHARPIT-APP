import Testing
@testable import Sharpit

@Test func aProgressFractionIsHeldToTheBar() {
    #expect(SharpitProgressMath.clamped(-0.2) == 0)
    #expect(SharpitProgressMath.clamped(0.4) == 0.4)
    #expect(SharpitProgressMath.clamped(1.7) == 1)
    #expect(SharpitProgressMath.clamped(.nan) == 0)
}

@Test func aGoalTrackMeasuresTowardAFasterTime() {
    // 23:02 previous best, 22:14 now, 21:00 goal — seconds going down.
    let fraction = SharpitProgressMath.fraction(start: 1382, current: 1334, goal: 1260)
    #expect(abs(fraction - 48.0 / 122.0) < 0.0001)
}

@Test func aGoalTrackMeasuresTowardAHeavierLoad() {
    #expect(SharpitProgressMath.fraction(start: 97.5, current: 102.5, goal: 110) == 0.4)
}

@Test func aGoalTrackNeverOvershootsOrDividesByZero() {
    #expect(SharpitProgressMath.fraction(start: 100, current: 120, goal: 110) == 1)
    #expect(SharpitProgressMath.fraction(start: 100, current: 90, goal: 110) == 0)
    #expect(SharpitProgressMath.fraction(start: 100, current: 100, goal: 100) == 1)
}

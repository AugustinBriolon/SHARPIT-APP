import Testing
@testable import Sharpit

@Test func aRingWithNoDataDrawsNoArc() {
    #expect(CliniqueRingMath.trim(for: nil) == 0)
}

@Test func aRingArcIsHeldToTheCircle() {
    #expect(CliniqueRingMath.trim(for: 0.64) == 0.64)
    #expect(CliniqueRingMath.trim(for: 1.4) == 1)
    #expect(CliniqueRingMath.trim(for: -0.1) == 0)
    #expect(CliniqueRingMath.trim(for: .nan) == 0)
}

@Test func everyPillarHasItsOwnGlyph() {
    let symbols = Set(CliniquePillar.allCases.map(\.symbol))
    #expect(symbols.count == CliniquePillar.allCases.count)
}

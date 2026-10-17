import Testing
@testable import Sharpit

/// The « Analyse du coach » card only offers what the server reads on request; a tap on any
/// other sport used to end on a generic error.
struct CoachAnalysisAvailabilityTests {
    @Test(arguments: [V1ActivityType.run, .bike, .swim, .triathlon, .strength])
    func offersAnalysisForReadSports(_ type: V1ActivityType) {
        #expect(type.supportsCoachAnalysis)
    }

    @Test(arguments: [V1ActivityType.hike, .other])
    func hidesAnalysisForOtherSports(_ type: V1ActivityType) {
        #expect(!type.supportsCoachAnalysis)
    }
}

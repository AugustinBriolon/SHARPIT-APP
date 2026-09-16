import Foundation
import Testing
@testable import Sharpit

@MainActor
@Test func arrivalDirectorReduceMotionSnapsToIdle() async {
    var phases: [TodayArrivalPhase] = []
    await TodayArrivalDirector.run(reduceMotion: true, gaugeCount: 2) { phase in
        phases.append(phase)
    }
    #expect(phases == [.idle])
}

@MainActor
@Test func arrivalDirectorPhasesIncludeCausalOrder() async {
    var phases: [TodayArrivalPhase] = []
    await TodayArrivalDirector.run(reduceMotion: false, gaugeCount: 0) { phase in
        phases.append(phase)
    }
    if SharpitMotion.reduceMotion {
        #expect(phases == [.idle])
        return
    }
    #expect(phases.first == .plate)
    #expect(phases.contains(.session))
    #expect(phases.contains(.gauges))
    #expect(phases.last == .idle)
}

@Test func arrivalPhaseVisibilityFlags() {
    #expect(TodayArrivalPhase.hidden.showsPlate == false)
    #expect(TodayArrivalPhase.plate.showsPlate == true)
    #expect(TodayArrivalPhase.plate.showsSession == false)
    #expect(TodayArrivalPhase.session.showsSession == true)
    #expect(TodayArrivalPhase.session.showsGauges == false)
    #expect(TodayArrivalPhase.gauges.showsGauges == true)
    #expect(TodayArrivalPhase.idle.showsGauges == true)
}

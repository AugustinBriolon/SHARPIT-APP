import Testing
@testable import Sharpit

@Test func shellDestinationsMatchTabCopy() {
    #expect(ShellDestination.plan.title == "Plan")
    #expect(ShellDestination.coach.title == "Coach")
    #expect(ShellDestination.activity.title == "Activité")
    #expect(ShellDestination.me.title == "Moi")
}

@Test func planShellIsIconFirst() {
    #expect(ShellDestination.plan.horizonCue == "7–14 j")
    #expect(ShellDestination.plan.surfaces.map(\.label) == ["Semaine", "Bilan", "Objectif"])
    #expect(ShellDestination.plan.surfaces.allSatisfy { !$0.symbolName.isEmpty })
}

@Test func meShellListsAthleteSurfaces() {
    #expect(ShellDestination.me.surfaces.map(\.label) == ["Corps", "Objectifs", "Privé"])
}

@Test func signalKeysExposeSymbols() {
    #expect(V1TodaySignalKey.sleep.instrumentSymbol == "moon.zzz")
    #expect(V1TodaySignalKey.effort.instrumentSymbol == "bolt")
}

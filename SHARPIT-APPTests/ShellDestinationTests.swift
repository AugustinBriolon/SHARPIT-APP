import Testing
@testable import Sharpit

@Test func shellDestinationsMatchTabCopy() {
    #expect(ShellDestination.plan.title == "Plan")
    #expect(ShellDestination.coach.title == "Coach")
    #expect(ShellDestination.activity.title == "Activité")
    #expect(ShellDestination.body.title == "Corps")
}

@Test func planShellIsIconFirst() {
    #expect(ShellDestination.plan.horizonCue == "7–14 j")
    #expect(ShellDestination.plan.surfaces.map(\.label) == ["Semaine", "Bilan", "Objectif"])
    #expect(ShellDestination.plan.surfaces.allSatisfy { !$0.symbolName.isEmpty })
}

@Test func bodyShellListsItsSections() {
    #expect(ShellDestination.body.surfaces.map(\.label) == ["Composition", "Récupération", "Seuils"])
}

@Test func signalKeysExposeSymbols() {
    #expect(V1TodaySignalKey.sleep.instrumentSymbol == "moon.zzz")
    #expect(V1TodaySignalKey.effort.instrumentSymbol == "bolt")
}

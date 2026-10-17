import Foundation
import Testing
@testable import Sharpit

// MARK: - Sports & équipement

@Test func aSportRowCountsOnlyTheKitOfThatSport() {
    let owned: Set<String> = ["run_treadmill", "bike_home_trainer"]

    #expect(SportsReadout.equipmentSummary(sportId: "run", owned: owned, venue: .bodyweight) == "1 équipement")
    #expect(SportsReadout.equipmentSummary(sportId: "swim", owned: owned, venue: .bodyweight) == "Aucun matériel renseigné")
}

@Test func triathlonCountsItsThreeLegs() {
    let owned: Set<String> = ["run_treadmill", "bike_home_trainer"]

    #expect(SportsReadout.equipmentSummary(sportId: "triathlon", owned: owned, venue: .bodyweight) == "2 équipements")
}

@Test func strengthLeadsWithWhereTheAthleteTrains() {
    let summary = SportsReadout.equipmentSummary(sportId: "strength", owned: [], venue: .gym)

    #expect(summary.hasPrefix("Salle · "))
}

/// Strength alone is plannable (SHARPIT ADR-086); mobility alone is not.
@Test func theLastSportThatMakesAPlanCannotLeave() {
    #expect(SportsReadout.canRemove("run", from: ["run", "strength"]))
    #expect(SportsReadout.canRemove("run", from: ["run", "bike"]))
    #expect(SportsReadout.canRemove("strength", from: ["run", "strength"]))
    #expect(!SportsReadout.canRemove("strength", from: ["strength", "mobility"]))
    #expect(!SportsReadout.canRemove("run", from: ["run", "mobility"]))
}

@Test func thePlusOffersOnlyTheSportsNotYetPracticed() {
    let ids = SportsReadout.addable(to: ["run", "strength"]).map(\.id)

    #expect(ids == ["bike", "swim", "triathlon", "mobility", "stretching"])
    #expect(SportsReadout.addable(to: Set(PracticedSportCatalog.all.map(\.id))).isEmpty)
}

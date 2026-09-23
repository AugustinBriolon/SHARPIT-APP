import Foundation
import Testing
@testable import Sharpit

@Test func equipmentPatchCarriesExpectedJsonShape() throws {
    var patch = AthleteProfilePatch()
    let eq = V1AthleteEquipment(
        version: 1,
        strengthVenue: "home",
        owned: ["run_track", "bike_home_trainer"]
    )
    patch.setEquipment(eq)

    #expect(patch.fields.keys.contains("equipment"))
    guard case .object(let dict) = patch.fields["equipment"] else {
        Issue.record("Expected object in equipment patch")
        return
    }
    #expect(dict["version"] == .number(1))
    #expect(dict["strengthVenue"] == .string("home"))
    #expect(dict["owned"] == .array([.string("run_track"), .string("bike_home_trainer")]))
}

@Test func practicedSportsPatchCarriesExpectedJsonShape() throws {
    var patch = AthleteProfilePatch()
    let sports = V1AthletePracticedSports(
        version: 1,
        sports: ["run", "bike", "strength"]
    )
    patch.setPracticedSports(sports)

    #expect(patch.fields.keys.contains("practicedSports"))
    guard case .object(let dict) = patch.fields["practicedSports"] else {
        Issue.record("Expected object in practicedSports patch")
        return
    }
    #expect(dict["version"] == .number(1))
    #expect(dict["sports"] == .array([.string("run"), .string("bike"), .string("strength")]))
}

@Test func equipmentCatalogFiltersHomeItemsBasedOnVenue() {
    let homeItemsWithGym = EquipmentCatalog.items(for: .strength, venue: .gym)
    let homeItemsWithHome = EquipmentCatalog.items(for: .strength, venue: .home)
    let homeItemsWithBoth = EquipmentCatalog.items(for: .strength, venue: .both)
    let homeItemsWithBodyweight = EquipmentCatalog.items(for: .strength, venue: .bodyweight)

    // Gym or bodyweight alone excludes items requiring home equipment (like dumbbells, barbell, bench)
    #expect(!homeItemsWithGym.contains(where: { $0.id == "strength_dumbbells" }))
    #expect(!homeItemsWithBodyweight.contains(where: { $0.id == "strength_dumbbells" }))

    // Home and Both include dumbbells
    #expect(homeItemsWithHome.contains(where: { $0.id == "strength_dumbbells" }))
    #expect(homeItemsWithBoth.contains(where: { $0.id == "strength_dumbbells" }))

    // Weighted vest does not require home setup, so it is present everywhere
    #expect(homeItemsWithGym.contains(where: { $0.id == "strength_weighted_vest" }))
    #expect(homeItemsWithBodyweight.contains(where: { $0.id == "strength_weighted_vest" }))
}

@Test func equipmentAndPracticedSportsDecodesFromProfileJson() throws {
    let json = """
    {
        "displayMode": "essential",
        "equipment": {
            "version": 1,
            "strengthVenue": "both",
            "owned": ["bike_power_meter", "swim_fins"]
        },
        "practicedSports": {
            "version": 1,
            "sports": ["run", "bike", "swim", "triathlon", "strength"]
        }
    }
    """
    let profile = try JSONDecoder().decode(V1AthleteProfile.self, from: Data(json.utf8))
    #expect(profile.equipment != nil)
    #expect(profile.equipment?.strengthVenue == "both")
    #expect(profile.equipment?.owned == ["bike_power_meter", "swim_fins"])
    #expect(profile.practicedSports != nil)
    #expect(profile.practicedSports?.sports == ["run", "bike", "swim", "triathlon", "strength"])
}

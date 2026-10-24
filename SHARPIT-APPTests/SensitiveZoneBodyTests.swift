import Foundation
import Testing
@testable import Sharpit

private func spot(_ part: String, _ side: SensitiveZoneBody.Side, _ face: SensitiveZoneBody.Face = .front) throws -> SensitiveZoneBody.Spot {
    try #require(SensitiveZoneBody.spots.first { $0.part == part && $0.side == side && $0.face == face })
}

@Test func everyPartTheWebOffersHasAPlaceOnTheBody() {
    for part in OnboardingInjuryDraft.bodyParts {
        #expect(SensitiveZoneBody.isOnMap(part), "\(part)")
    }
}

@Test func theFrontMirrorsTheAthletesSidesAndTheBackDoesNot() throws {
    #expect(try spot("Genou", .left).x > 0.5)
    #expect(try spot("Épaule", .left, .back).x < 0.5)
}

@Test func aTapOnAPairedPartTakesItsSideAndBothSidesReadBilateral() throws {
    let left = try spot("Genou", .left), right = try spot("Genou", .right)

    var picked = SensitiveZoneBody.select(left, part: nil, side: "NA")
    #expect(picked.part == "Genou" && picked.side == "LEFT")
    picked = SensitiveZoneBody.select(right, part: picked.part, side: picked.side)
    #expect(picked.side == "BILATERAL")
    #expect(SensitiveZoneBody.isSelected(left, part: picked.part, side: picked.side))
    picked = SensitiveZoneBody.select(left, part: picked.part, side: picked.side)
    #expect(picked.part == "Genou" && picked.side == "RIGHT")
    picked = SensitiveZoneBody.select(right, part: picked.part, side: picked.side)
    #expect(picked.part == nil)
}

@Test func aSinglePartHasNoSideAndAnotherPartReplacesIt() throws {
    let back = try spot("Lombaires", .none, .back)
    let picked = SensitiveZoneBody.select(back, part: "Genou", side: "BILATERAL")
    #expect(picked.part == "Lombaires" && picked.side == "NA")
    #expect(SensitiveZoneBody.select(back, part: "Lombaires", side: "NA").part == nil)
}

@Test func aPartOpensOnTheFaceThatShowsIt() {
    #expect(SensitiveZoneBody.face(for: "Ischio") == .back)
    #expect(SensitiveZoneBody.face(for: "Épaule") == .front)
    #expect(SensitiveZoneBody.face(for: nil) == .front)
}

@Test func theChosenZoneIsNamedInPlainFrench() {
    #expect(SensitiveZoneBody.caption(part: "Genou", side: "LEFT") == "Genou gauche")
    #expect(SensitiveZoneBody.caption(part: "Épaule", side: "RIGHT") == "Épaule droite")
    #expect(SensitiveZoneBody.caption(part: "Mollet", side: "BILATERAL") == "Mollet · des deux côtés")
    #expect(SensitiveZoneBody.caption(part: "Dos", side: "NA") == "Dos")
}

@Test func onlyThePartsTheServerOffersAreDrawn() {
    let spots = SensitiveZoneBody.spots(on: .front, offered: ["Genou"])
    #expect(spots.count == 2)
    #expect(spots.allSatisfy { $0.part == "Genou" })
}

/// The web's `COMMON_BODY_PARTS`: none of them should fall back to a chip under the body.
@Test func everyCommonBodyPartHasAPlaceOnTheBody() {
    let common = [
        "Pied", "Cheville", "Tendon d'Achille", "Mollet", "Tibia", "Genou", "Quadriceps", "Ischio",
        "Adducteurs", "Hanche", "Fessier", "Psoas", "Bassin", "Abdominaux", "Lombaires", "Dos",
        "Trapèzes", "Épaule", "Pectoraux", "Cou", "Bras", "Coude", "Poignet",
    ]
    for part in common {
        #expect(SensitiveZoneBody.isOnMap(part), "\(part)")
    }
}

@Test func aTapOffEveryDotTakesTheNearestPartWithinReach() throws {
    let spots = SensitiveZoneBody.spots(on: .front, offered: ["Genou", "Cheville"])
    let knee = try spot("Genou", .left)
    let near = SensitiveZoneBody.nearest(to: CGPoint(x: knee.x + 0.02, y: knee.y + 0.02), in: spots)
    #expect(near == knee)
    #expect(SensitiveZoneBody.nearest(to: CGPoint(x: 0.5, y: 0.1), in: spots) == nil)
}

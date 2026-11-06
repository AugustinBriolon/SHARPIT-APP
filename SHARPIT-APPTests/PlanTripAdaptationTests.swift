import Foundation
import Testing
@testable import Sharpit

private func conflict(
    type: CoachMemoryType = .travel,
    name: String = "Lyon",
    from start: String = "2026-11-07",
    to end: String = "2026-11-08",
    constraint: TravelTrainingConstraint = .none,
    sessions: Int = 2
) -> V1TodayTravelConflict {
    V1TodayTravelConflict(
        travelId: "trip", type: type, name: name, startDate: start, endDate: end,
        trainingConstraint: constraint, sessionCount: sessions
    )
}

@Test func theTodayPayloadCarriesTheConflict() throws {
    let json = """
    {"travelId": "trip", "type": "TRAVEL", "name": "Lyon", "startDate": "2026-11-07",
     "endDate": "2026-11-08", "trainingConstraint": "REDUCED", "sessionCount": 3}
    """
    let decoded = try JSONDecoder().decode(V1TodayTravelConflict.self, from: Data(json.utf8))
    #expect(decoded == conflict(constraint: .reduced, sessions: 3))
}

@Test func theCardNamesTheTripAndCountsTheSessions() {
    let trip = conflict()
    #expect(TravelConflictReadout.title(trip) == "Ton déplacement à Lyon bouscule ton plan")
    #expect(TravelConflictReadout.subtitle(trip).hasPrefix("2 séances ne collent pas, du "))
    #expect(TravelConflictReadout.subtitle(conflict(sessions: 1)).hasPrefix("1 séance ne colle pas"))
}

@Test func aOneDayConstraintReadsAsOneDay() {
    let work = conflict(type: .constraint, name: "Boulot", from: "2026-11-09", to: "2026-11-09")
    #expect(TravelConflictReadout.title(work) == "« Boulot » bouscule ton plan")
    #expect(TravelConflictReadout.days(work).hasPrefix("le "))
}

@Test func theCoachIsToldThePlaceTheDaysAndTheTraining() {
    let focus = PlanTripAdaptation.focus(for: conflict())
    #expect(focus.hasPrefix("Je suis en déplacement à Lyon du "))
    #expect(focus.contains("pas d'entraînement possible"))
    #expect(focus.contains("séances clés"))
}

import Testing
@testable import Sharpit

// The labels and the `discussKind` strings are the web's, unchanged (ADR-030, ADR-031):
// the athlete meets the same chip on both surfaces and the server reads one discriminant.
// A drift here is a drift in the product, not a cosmetic difference.

@Test func discussKindsMatchTheWebDiscriminants() {
    #expect(CoachDiscussTarget.today.kind == "today")
    #expect(CoachDiscussTarget.plannedSession(sessionId: "s-1").kind == "planned-session")
    #expect(CoachDiscussTarget.activity(activityId: "a-1").kind == "activity")
    #expect(CoachDiscussTarget.planning(horizonDays: 7).kind == "planning")
}

@Test func aNamedTargetReadsAsTheWebWritesIt() {
    #expect(CoachDiscuss.describe(.today).label == "Ton état du jour")
    #expect(
        CoachDiscuss.describe(.activity(activityId: "a-1"), name: "Sortie longue").label
            == "Séance réalisée · Sortie longue"
    )
    #expect(
        CoachDiscuss.describe(.plannedSession(sessionId: "s-1"), name: "Seuil 40 min").label
            == "Séance prévue · Seuil 40 min"
    )
    #expect(
        CoachDiscuss.describe(.planning(horizonDays: 7)).label == "Ta semaine · les 7 prochains jours"
    )
}

@Test func anUnnamedTargetDegradesRatherThanInventingAName() {
    #expect(CoachDiscuss.describe(.activity(activityId: "a-1")).label == "Une séance réalisée")
    #expect(CoachDiscuss.describe(.plannedSession(sessionId: "s-1")).label == "Une séance prévue")
}

@Test func blankNamesCountAsMissing() {
    #expect(CoachDiscuss.describe(.activity(activityId: "a-1"), name: "   ").label == "Une séance réalisée")
    #expect(CoachDiscuss.describe(.activity(activityId: "a-1"), name: "").label == "Une séance réalisée")
}

@Test func namesAreTrimmedBeforeTheyReachTheLabel() {
    #expect(
        CoachDiscuss.describe(.activity(activityId: "a-1"), name: "  Sortie longue  ").label
            == "Séance réalisée · Sortie longue"
    )
}

@Test func planningHorizonsReadInPlainFrench() {
    #expect(CoachDiscuss.planningHorizonLabel(1) == "demain")
    #expect(CoachDiscuss.planningHorizonLabel(3) == "les 3 prochains jours")
    #expect(CoachDiscuss.planningHorizonLabel(7) == "les 7 prochains jours")
    #expect(CoachDiscuss.planningHorizonLabel(14) == "les 14 prochains jours")
    #expect(CoachDiscuss.planningHorizonLabel(21) == "21 jours")
}

@Test func metadataCarriesTheKindAndItsTargetId() {
    let activity = CoachDiscuss.describe(.activity(activityId: "a-1")).metadata
    #expect(activity["discussKind"] == .string("activity"))
    #expect(activity["activityId"] == .string("a-1"))

    let planned = CoachDiscuss.describe(.plannedSession(sessionId: "s-1")).metadata
    #expect(planned["discussKind"] == .string("planned-session"))
    #expect(planned["sessionId"] == .string("s-1"))

    let planning = CoachDiscuss.describe(.planning(horizonDays: 7)).metadata
    #expect(planning["discussKind"] == .string("planning"))
    // A number, not "7": the server checks it against a set of numbers.
    #expect(planning["horizonDays"] == .number(7))

    #expect(CoachDiscuss.describe(.today).metadata == ["discussKind": .string("today")])
}

@MainActor
@Test func discussingSendsTheAthleteToCoachCarryingTheSubject() {
    let router = ShellRouter()
    let context = CoachDiscuss.describe(.activity(activityId: "a-1"), name: "Sortie longue")

    router.discussWithCoach(about: context)

    #expect(router.selectedTab == .coach)
    #expect(router.pendingCoachContext == context)
}

@MainActor
@Test func theContextIsConsumedOnceSoItCannotReattachLater() {
    let router = ShellRouter()
    router.discussWithCoach(about: CoachDiscuss.describe(.today))

    #expect(router.consumeCoachContext() != nil)
    #expect(router.consumeCoachContext() == nil)
    #expect(router.pendingCoachContext == nil)
}

@MainActor
@Test func selectingATabDoesNotAttachAnyContext() {
    let router = ShellRouter()
    router.select(.plan)

    #expect(router.selectedTab == .plan)
    #expect(router.pendingCoachContext == nil)
}

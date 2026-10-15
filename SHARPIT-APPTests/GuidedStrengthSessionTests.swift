import Foundation
import Testing
@testable import Sharpit

@Test func aPrescriptionExpandsIntoOneTargetPerSet() {
    let prescription: JSONValue = .object([
        "version": .number(1),
        "sets": .array([
            .object([
                "exercise": .string("Squat"),
                "sets": .number(3),
                "reps": .number(8),
                "weightKg": .number(60),
                "restSec": .number(90),
                "restMode": .string("time"),
                "order": .number(0),
            ]),
            .object([
                "exercise": .string("Étirement 90/90"),
                "sets": .number(2),
                "reps": .number(0),
                "durationSec": .number(45),
                "order": .number(1),
            ]),
        ]),
    ])

    let session = GuidedStrengthSession.make(
        title: "Force + mobilité",
        plannedSessionId: "ps-1",
        prescription: prescription
    )

    #expect(session?.targets.count == 5)
    #expect(session?.targets.prefix(3).allSatisfy { $0.exerciseName == "Squat" } == true)
    #expect(session?.targets[0].restIsTimed == true)
    #expect(session?.targets[0].restSec == 90)
    #expect(session?.targets[3].isHold == true)
    #expect(session?.targets[3].targetDurationSec == 45)
}

@Test func completingSetsBuildsAStrengthActivityPayload() throws {
    let prescription: JSONValue = .object([
        "version": .number(1),
        "sets": .array([
            .object([
                "exercise": .string("Squat"),
                "sets": .number(3),
                "reps": .number(8),
                "weightKg": .number(60),
                "order": .number(0),
            ]),
            .object([
                "exercise": .string("Planche"),
                "sets": .number(2),
                "reps": .number(0),
                "durationSec": .number(40),
                "order": .number(1),
            ]),
        ]),
    ])
    var session = try #require(GuidedStrengthSession.make(
        title: "Muscu",
        plannedSessionId: "ps-2",
        prescription: prescription,
        startedAt: Date(timeIntervalSince1970: 1_800_000_000)
    ))

    // Two squat sets at 70 kg / 6 reps, skip the third; one plank hold.
    session.targets[0].loggedReps = 6
    session.targets[0].loggedWeightKg = 70
    session.completeCurrent()
    session.targets[1].loggedReps = 6
    session.targets[1].loggedWeightKg = 70
    session.completeCurrent()
    session.skipCurrent()
    session.targets[3].loggedDurationSec = 40
    session.completeCurrent()
    session.skipCurrent()

    let draft = session.activityDraft(
        finishedAt: Date(timeIntervalSince1970: 1_800_000_000 + 25 * 60),
        rpe: 7,
        feeling: .good
    )
    #expect(draft.sport == .strength)
    #expect(draft.title == "Muscu")
    #expect(draft.durationMin == 25)
    #expect(draft.rpe == 7)
    #expect(draft.feeling == .good)
    #expect(draft.exercises.map(\.name) == ["Squat", "Planche"])
    #expect(draft.exercises[0].sets == 2)
    #expect(draft.exercises[0].reps == 6)
    #expect(draft.exercises[0].weightKg == 70)
    #expect(draft.exercises[1].sets == 1)
    #expect(draft.exercises[1].durationSec == 40)

    let sets = draft.creation()["strengthSets"]?.array
    #expect(sets?.count == 2)
    #expect(sets?[0]["exercise"] == .string("Squat"))
    #expect(sets?[0]["sets"] == .number(2))
    #expect(sets?[0]["reps"] == .number(6))
    #expect(sets?[0]["weightKg"] == .number(70))
    #expect(sets?[1]["durationSec"] == .number(40))
    #expect(sets?[1]["reps"] == .number(1))
}

@Test func previousSetValuesCarryToTheNextOfTheSameExercise() throws {
    let prescription: JSONValue = .object([
        "sets": .array([
            .object([
                "exercise": .string("Deadlift"),
                "sets": .number(2),
                "reps": .number(5),
                "weightKg": .number(100),
                "order": .number(0),
            ]),
        ]),
    ])
    var session = try #require(GuidedStrengthSession.make(
        title: "DL",
        plannedSessionId: nil,
        prescription: prescription
    ))
    session.targets[0].loggedReps = 4
    session.targets[0].loggedWeightKg = 110
    session.completeCurrent()
    #expect(session.targets[1].loggedReps == 4)
    #expect(session.targets[1].loggedWeightKg == 110)
}

@Test func addingASetExtendsTheExerciseAndKeepsOrder() throws {
    let prescription: JSONValue = .object([
        "sets": .array([
            .object([
                "exercise": .string("Bench Press"),
                "sets": .number(2),
                "reps": .number(8),
                "weightKg": .number(60),
                "order": .number(0),
            ]),
        ]),
    ])
    var session = try #require(GuidedStrengthSession.make(
        title: "Push",
        plannedSessionId: nil,
        prescription: prescription
    ))
    #expect(session.exerciseGroups.count == 1)
    #expect(session.targets.count == 2)
    session.addSet(toExercise: "Bench Press")
    #expect(session.targets.count == 3)
    #expect(session.targets.map(\.setNumber) == [1, 2, 3])
    #expect(session.targets.map(\.setCount) == [3, 3, 3])

    let removed = session.targets[1].id
    #expect(session.canRemoveSet(id: removed))
    session.removeSet(id: removed)
    #expect(session.targets.count == 2)
    #expect(session.targets.map(\.setNumber) == [1, 2])
    session.removeSet(id: session.targets[1].id)
    #expect(session.targets.count == 1)
    #expect(!session.canRemoveSet(id: session.targets[0].id))
    session.removeSet(id: session.targets[0].id)
    #expect(session.targets.count == 1)
}

@Test func prescriptionCatalogIdResolvesToGymVisualGifURL() throws {
    let prescription: JSONValue = .object([
        "version": .number(1),
        "sets": .array([
            .object([
                "exercise": .string("Développé couché barre"),
                "exerciseCatalogId": .string("0025"),
                "sets": .number(1),
                "reps": .number(8),
                "order": .number(0),
            ]),
        ]),
    ])
    var session = try #require(GuidedStrengthSession.make(
        title: "Push",
        plannedSessionId: nil,
        prescription: prescription
    ))
    #expect(session.targets[0].exerciseCatalogId == "0025")
    #expect(session.exerciseGroups[0].exerciseCatalogId == "0025")

    let gif = try #require(ExerciseMediaCatalog.gifURL(catalogId: "0025"))
    #expect(gif.absoluteString.contains("/videos/0025-"))
    #expect(gif.pathExtension == "gif")

    session.addSet(toExercise: "Développé couché barre")
    #expect(session.targets.last?.exerciseCatalogId == "0025")
}

@Test func frenchExerciseNameResolvesMediaWithoutCatalogId() throws {
    let prescription: JSONValue = .object([
        "version": .number(1),
        "sets": .array([
            .object([
                "exercise": .string("Pompe"),
                "sets": .number(1),
                "reps": .number(10),
                "order": .number(0),
            ]),
        ]),
    ])
    let session = try #require(GuidedStrengthSession.make(
        title: "Push",
        plannedSessionId: nil,
        prescription: prescription
    ))
    #expect(session.targets[0].exerciseCatalogId == "0662")
    #expect(ExerciseMediaCatalog.thumbURL(name: "Pompe") != nil)
    #expect(ExerciseMediaCatalog.resolveCatalogId(name: "Développé couché barre") == "0025")
}

@Test func aPlanPreviewCarriesItsStrengthPrescriptionForPhoneFollow() {
    let prescription: JSONValue = .object([
        "version": .number(1),
        "sets": .array([
            .object(["exercise": .string("Squat"), "sets": .number(3), "reps": .number(8), "order": .number(0)]),
        ]),
    ])
    let session = V1PlannedSessionItem(
        id: "ps-strength",
        date: Date(timeIntervalSince1970: 1_789_000_000),
        title: "Force",
        type: "STRENGTH",
        durationMin: 40,
        strengthPrescription: prescription
    )
    let preview = PlannedSessionPreview(session: session)
    #expect(preview.canFollowOnPhone)
    #expect(preview.strengthPrescription != nil)
}

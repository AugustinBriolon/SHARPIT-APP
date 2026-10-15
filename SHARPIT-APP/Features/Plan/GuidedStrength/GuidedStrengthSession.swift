import Foundation

/// One prescribed set the athlete ticks off on the phone — Strong's CellSet, without the grid.
struct GuidedStrengthSetTarget: Identifiable, Equatable, Sendable {
    let id: UUID
    let exerciseName: String
    /// Stable catalog handle for form media (Gym Visual via exercises-dataset).
    let exerciseCatalogId: String?
    var setNumber: Int
    var setCount: Int
    let targetReps: Int
    let targetWeightKg: Double?
    let targetDurationSec: Int?
    let restSec: Int?
    let restIsTimed: Bool
    let notes: String?

    var loggedReps: Int
    var loggedWeightKg: Double?
    var loggedDurationSec: Int?
    var isDone: Bool
    var isSkipped: Bool

    var isHold: Bool { (targetDurationSec ?? 0) > 0 && targetReps == 0 }

    var targetLine: String {
        if let duration = targetDurationSec, duration > 0, targetReps == 0 {
            return PlannedSessionFormat.durationSeconds(duration)
        }
        var parts = ["\(targetReps) rep\(targetReps == 1 ? "" : "s")"]
        if let kg = targetWeightKg { parts.append(Self.kilograms(kg)) }
        return parts.joined(separator: " · ")
    }

    /// `12 × 95 kg` as logged (or the prescription when still open).
    var readoutLine: String {
        if isHold {
            let sec = loggedDurationSec ?? targetDurationSec ?? 0
            return PlannedSessionFormat.durationSeconds(sec)
        }
        let reps = isDone ? loggedReps : max(loggedReps, targetReps)
        let kg = isDone ? loggedWeightKg : (loggedWeightKg ?? targetWeightKg)
        if let kg {
            return "\(reps) × \(Self.kilograms(kg))"
        }
        return "\(reps) rep\(reps == 1 ? "" : "s")"
    }

    static func kilograms(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded)) kg" }
        return String(format: "%.1f kg", rounded).replacingOccurrences(of: ".", with: ",")
    }

    /// Volume figure without the unit, for the Strong-style header (`3 590`).
    static func volumeFigure(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value.rounded())) ?? "\(Int(value.rounded()))"
    }
}

/// One exercise block in the session overview / detail card.
struct GuidedStrengthExerciseGroup: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let exerciseCatalogId: String?
    let notes: String?
    let indices: [Int]

    func volumeKg(in targets: [GuidedStrengthSetTarget]) -> Double {
        indices.reduce(0) { partial, index in
            guard targets.indices.contains(index), targets[index].isDone else { return partial }
            let set = targets[index]
            let kg = set.loggedWeightKg ?? 0
            return partial + kg * Double(max(set.loggedReps, 1))
        }
    }

    func doneCount(in targets: [GuidedStrengthSetTarget]) -> Int {
        indices.filter { targets[$0].isDone }.count
    }
}

/// A phone-guided STRENGTH / mobilité workout expanded from `strengthPrescription`.
struct GuidedStrengthSession: Equatable, Sendable {
    let title: String
    let plannedSessionId: String?
    var targets: [GuidedStrengthSetTarget]
    let startedAt: Date

    /// Expands each prescribed exercise into N set rows. Nil when there is nothing to follow.
    static func make(
        title: String,
        plannedSessionId: String?,
        prescription: JSONValue?,
        startedAt: Date = .now
    ) -> GuidedStrengthSession? {
        let exercises = StrengthExerciseDraft.exercises(in: prescription).filter(\.isNamed)
        guard !exercises.isEmpty else { return nil }

        var targets: [GuidedStrengthSetTarget] = []
        for exercise in exercises {
            let count = max(exercise.sets, 1)
            let restIsTimed = exercise.restMode == "time" || (exercise.restMode == nil && (exercise.restSec ?? 0) > 0)
            for number in 1...count {
                let exerciseName = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let catalogId = ExerciseMediaCatalog.resolveCatalogId(
                    catalogId: exercise.exerciseCatalogId,
                    name: exerciseName
                )
                targets.append(
                    GuidedStrengthSetTarget(
                        id: UUID(),
                        exerciseName: exerciseName,
                        exerciseCatalogId: catalogId,
                        setNumber: number,
                        setCount: count,
                        targetReps: exercise.reps,
                        targetWeightKg: exercise.weightKg,
                        targetDurationSec: exercise.durationSec,
                        restSec: exercise.restSec,
                        restIsTimed: restIsTimed && (exercise.restSec ?? 0) > 0,
                        notes: number == 1 ? exercise.notes : nil,
                        loggedReps: max(exercise.reps, exercise.durationSec == nil ? 1 : 0),
                        loggedWeightKg: exercise.weightKg,
                        loggedDurationSec: exercise.durationSec,
                        isDone: false,
                        isSkipped: false
                    )
                )
            }
        }
        return GuidedStrengthSession(
            title: title,
            plannedSessionId: plannedSessionId,
            targets: targets,
            startedAt: startedAt
        )
    }

    var exerciseGroups: [GuidedStrengthExerciseGroup] {
        var order: [String] = []
        var indices: [String: [Int]] = [:]
        var notes: [String: String?] = [:]
        var catalogIds: [String: String?] = [:]
        for (index, target) in targets.enumerated() {
            if indices[target.exerciseName] == nil {
                order.append(target.exerciseName)
                indices[target.exerciseName] = []
                notes[target.exerciseName] = target.notes
                catalogIds[target.exerciseName] = target.exerciseCatalogId
            }
            indices[target.exerciseName]?.append(index)
        }
        return order.map { name in
            GuidedStrengthExerciseGroup(
                name: name,
                exerciseCatalogId: catalogIds[name] ?? nil,
                notes: notes[name] ?? nil,
                indices: indices[name] ?? []
            )
        }
    }

    var currentIndex: Int {
        targets.firstIndex { !$0.isDone && !$0.isSkipped } ?? targets.count
    }

    var current: GuidedStrengthSetTarget? {
        let index = currentIndex
        guard targets.indices.contains(index) else { return nil }
        return targets[index]
    }

    var isFinished: Bool { current == nil }

    var completedCount: Int { targets.filter(\.isDone).count }

    /// Completes a specific set (Strong-style tap on a row) and carries values forward.
    mutating func completeSet(id: UUID) {
        guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
        targets[index].isDone = true
        targets[index].isSkipped = false
        carryForward(from: index)
        renumber(exercise: targets[index].exerciseName)
    }

    mutating func uncompleteSet(id: UUID) {
        guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
        targets[index].isDone = false
        targets[index].isSkipped = false
    }

    mutating func completeCurrent() {
        let index = currentIndex
        guard targets.indices.contains(index) else { return }
        completeSet(id: targets[index].id)
    }

    mutating func skipCurrent() {
        let index = currentIndex
        guard targets.indices.contains(index) else { return }
        targets[index].isSkipped = true
        targets[index].isDone = false
    }

    /// Appends an open set cloned from the last row of that exercise (Strong « + Add a set »).
    mutating func addSet(toExercise name: String) {
        guard let lastIndex = targets.lastIndex(where: { $0.exerciseName == name }) else { return }
        let last = targets[lastIndex]
        let inserted = GuidedStrengthSetTarget(
            id: UUID(),
            exerciseName: name,
            exerciseCatalogId: last.exerciseCatalogId,
            setNumber: last.setNumber + 1,
            setCount: last.setCount + 1,
            targetReps: last.targetReps,
            targetWeightKg: last.targetWeightKg,
            targetDurationSec: last.targetDurationSec,
            restSec: last.restSec,
            restIsTimed: last.restIsTimed,
            notes: nil,
            loggedReps: last.loggedReps,
            loggedWeightKg: last.loggedWeightKg,
            loggedDurationSec: last.loggedDurationSec,
            isDone: false,
            isSkipped: false
        )
        targets.insert(inserted, at: lastIndex + 1)
        renumber(exercise: name)
    }

    /// Keeps at least one set per exercise so the card never goes empty mid-follow.
    func canRemoveSet(id: UUID) -> Bool {
        guard let name = targets.first(where: { $0.id == id })?.exerciseName else { return false }
        return targets.filter { $0.exerciseName == name }.count > 1
    }

    mutating func removeSet(id: UUID) {
        guard canRemoveSet(id: id),
              let index = targets.firstIndex(where: { $0.id == id }) else { return }
        let name = targets[index].exerciseName
        targets.remove(at: index)
        renumber(exercise: name)
    }

    /// Strong's previous-set button: the next undone set of the same exercise inherits the last log.
    private mutating func carryForward(from index: Int) {
        let source = targets[index]
        guard let next = targets[(index + 1)...].firstIndex(where: {
            $0.exerciseName == source.exerciseName && !$0.isDone && !$0.isSkipped
        }) else { return }
        targets[next].loggedReps = source.loggedReps
        targets[next].loggedWeightKg = source.loggedWeightKg
        targets[next].loggedDurationSec = source.loggedDurationSec
    }

    private mutating func renumber(exercise name: String) {
        let indices = targets.indices.filter { targets[$0].exerciseName == name }
        let count = indices.count
        for (offset, index) in indices.enumerated() {
            targets[index].setNumber = offset + 1
            targets[index].setCount = count
        }
    }

    /// Aggregated exercises for `ActivityDraft` — one row per named movement with completed sets.
    func activityExercises() -> [StrengthExerciseDraft] {
        var order: [String] = []
        var groups: [String: [GuidedStrengthSetTarget]] = [:]
        for target in targets where target.isDone {
            if groups[target.exerciseName] == nil {
                order.append(target.exerciseName)
                groups[target.exerciseName] = []
            }
            groups[target.exerciseName]?.append(target)
        }
        return order.compactMap { name in
            guard let done = groups[name], let last = done.last else { return nil }
            return StrengthExerciseDraft(
                name: name,
                sets: done.count,
                reps: last.loggedReps,
                weightKg: last.loggedWeightKg,
                durationSec: last.loggedDurationSec
            )
        }
    }

    func activityDraft(finishedAt: Date = .now, rpe: Int? = nil, feeling: SessionFeeling? = nil) -> ActivityDraft {
        let elapsed = max(Int(finishedAt.timeIntervalSince(startedAt) / 60), 1)
        var draft = ActivityDraft(date: startedAt)
        draft.sport = .strength
        draft.title = title
        draft.durationMin = elapsed
        draft.exercises = activityExercises()
        draft.rpe = rpe
        draft.feeling = feeling
        return draft
    }
}

extension PlannedSessionFormat {
    /// `45 s` / `1 min 30 s` for hold timers.
    static func durationSeconds(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        let rem = seconds % 60
        if rem == 0 { return "\(minutes) min" }
        return "\(minutes) min \(rem) s"
    }

    /// `1:00` countdown for the rest ring.
    static func restClock(_ seconds: Int) -> String {
        String(format: "%d:%02d", max(seconds, 0) / 60, max(seconds, 0) % 60)
    }

    /// `12:34` / `1:02:03` elapsed session clock.
    static func elapsedClock(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

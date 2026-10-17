import SwiftUI

/// A strength session's exercises as they were done, in order: each with its blocks of sets,
/// read at a glance — « 4 × 8 · 60 kg », « 3 × 45 s », « 3 × 12 » without a load.
nonisolated struct StrengthExerciseReadout: Equatable, Identifiable, Sendable {
    let exercise: String
    /// One line per block of identical sets, in the order the server sent them.
    let lines: [String]
    /// Kilograms moved (sets × reps × load); nil when nothing carried a load.
    let volumeKg: Double?

    var id: String { exercise }

    static func exercises(from sets: [V1ActivityStrengthSet]) -> [StrengthExerciseReadout] {
        var order: [String] = []
        var blocks: [String: [V1ActivityStrengthSet]] = [:]
        for set in sets {
            let name = set.exercise.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if blocks[name] == nil { order.append(name) }
            blocks[name, default: []].append(set)
        }
        return order.map { name in
            let rows = blocks[name] ?? []
            let loaded = rows.compactMap { row in row.weightKg.map { Double(row.sets * row.reps) * $0 } }
            return StrengthExerciseReadout(
                exercise: name,
                lines: rows.map(line),
                volumeKg: loaded.isEmpty ? nil : loaded.reduce(0, +)
            )
        }
    }

    static func line(_ set: V1ActivityStrengthSet) -> String {
        let effort = set.reps > 0 ? "\(set.reps)" : set.durationSec.map(seconds) ?? "–"
        let head = "\(set.sets) × \(effort)"
        guard let weight = set.weightKg, weight > 0 else { return head }
        return "\(head) · \(kilograms(weight))"
    }

    static func kilograms(_ value: Double) -> String {
        GuidedStrengthSetTarget.kilograms(value)
    }

    private static func seconds(_ value: Int) -> String {
        value >= 60 && value % 60 == 0 ? "\(value / 60) min" : "\(value) s"
    }
}

/// The session's exercises as the workout-summary reference card (ADR-085): a header with the
/// total volume, then one white row per exercise in the grey group — its ordinal, its name and
/// blocks of sets, its volume.
struct ActivityStrengthSection: View {
    let exercises: [StrengthExerciseReadout]

    private var totalVolume: Double? {
        let volumes = exercises.compactMap(\.volumeKg)
        return volumes.isEmpty ? nil : volumes.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            SharpitCardHeader(
                title: "Exercices",
                symbol: "dumbbell.fill",
                subtitle: exercises.count == 1 ? "1 exercice" : "\(exercises.count) exercices",
                showsChevron: false
            ) {
                if let totalVolume {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Volume")
                            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(SharpitColor.mutedForeground)
                        volumeFigure(totalVolume)
                    }
                }
            }

            SharpitInsetGroup {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    row(exercise, number: index + 1)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private func row(_ exercise: StrengthExerciseReadout, number: Int) -> some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            // The order always leads, so every row lines up; a picture, when the catalogue has one, trails.
            SharpitNumberChip(number: number)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exercise)
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(exercise.lines.joined(separator: " · "))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .subheadline, digits: true))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: SharpitSpacing.sm)
            if let volume = exercise.volumeKg {
                volumeFigure(volume)
            }
            if let thumb = ExerciseMediaCatalog.thumbURL(name: exercise.exercise) {
                GuidedExerciseThumbView(url: thumb, size: 40)
            }
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.sm)
        .frame(minHeight: SharpitSpacing.rowHeight)
        .sharpitSurface(.row)
        .accessibilityElement(children: .combine)
    }

    /// « 3 590 kg »: the figure bold, its unit muted, as the references write a load.
    private func volumeFigure(_ kilograms: Double) -> some View {
        SharpitRowFigure(
            value: StrengthExerciseReadout.kilograms(kilograms).replacingOccurrences(of: " kg", with: ""),
            unit: "kg"
        )
    }
}

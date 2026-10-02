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
        let rounded = (value * 10).rounded() / 10
        let text = rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
        return "\(text) kg"
    }

    private static func seconds(_ value: Int) -> String {
        value >= 60 && value % 60 == 0 ? "\(value / 60) min" : "\(value) s"
    }
}

struct ActivityStrengthSection: View {
    let exercises: [StrengthExerciseReadout]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Exercices")
            VStack(spacing: 0) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    row(exercise)
                    if index < exercises.count - 1 {
                        Rectangle()
                            .fill(SharpitColor.analysisGrid)
                            .frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, SharpitSpacing.md)
            .sharpitSurface(.panel)
            .sharpitCardSpecularBorder()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ exercise: StrengthExerciseReadout) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.exercise)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let volume = exercise.volumeKg {
                    Text("Volume \(StrengthExerciseReadout.kilograms(volume))")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            Spacer(minLength: SharpitSpacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(Array(exercise.lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(SharpitTypography.instrument)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                }
            }
        }
        .padding(.vertical, SharpitSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

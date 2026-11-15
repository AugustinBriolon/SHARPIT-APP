import SwiftUI

/// The session's breakdown — what to actually do, in order, as a table on the sheet: how long,
/// what, at what. Targets are already resolved server-side, so nothing here computes a band.
struct PlannedSessionBreakdownList: View {
    let steps: [V1PlannedSessionStep]
    let derived: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: SharpitSpacing.xs) {
                Text("Déroulé")
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if derived {
                    PlannedStepsEstimatedTag()
                }
            }
            PlannedStepTable(steps: steps)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The athlete did not write this breakdown; saying so is the honest version of showing it.
struct PlannedStepsEstimatedTag: View {
    var body: some View {
        Text("Estimé")
            .font(SharpitTypography.label)
            .tracking(SharpitTypography.labelTracking)
            .foregroundStyle(SharpitColor.slate)
            .padding(.horizontal, SharpitSpacing.xs)
            .padding(.vertical, 2)
            .background(SharpitColor.tile, in: Capsule())
    }
}

/// The steps as lines split by hairlines — the breakdown's own body, and a brick leg's.
///
/// A repeated set is named once (« 5 fois ») over the lines it repeats, which a rule down their
/// leading edge holds together: the block and its recovery are done five times, as a pair.
struct PlannedStepTable: View {
    let steps: [V1PlannedSessionStep]

    /// A table with illustrated exercises gives every line its slot — a quiet glyph where an
    /// exercise has no picture — so the names and doses line up down the page.
    private var hasPictures: Bool {
        steps.contains { ExerciseMediaCatalog.thumbURL(name: $0.label) != nil }
    }

    var body: some View {
        let sets = PlannedStepSet.sets(from: steps)
        let hasPictures = hasPictures
        VStack(spacing: 0) {
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                if index > 0 { CliniqueDivider() }
                if set.isRepeated {
                    RepeatedSet(set: set, hasPictures: hasPictures)
                } else {
                    ForEach(set.steps) { PlannedStepLine(step: $0, hasPictures: hasPictures) }
                }
            }
        }
    }
}

/// « 5 fois » over the steps it repeats.
private struct RepeatedSet: View {
    let set: PlannedStepSet
    let hasPictures: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("\(set.repeatCount) fois", systemImage: "repeat")
                .font(SharpitTypography.system(size: 13, weight: .semibold, relativeTo: .footnote, digits: true))
                .foregroundStyle(SharpitColor.slate)
                .padding(.top, 14)
            VStack(spacing: 0) {
                ForEach(Array(set.steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { CliniqueDivider() }
                    PlannedStepLine(step: step, hasPictures: hasPictures)
                }
            }
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Capsule().fill(SharpitColor.foreground).frame(width: 2).padding(.vertical, 14)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(set.repeatCount) fois : " + set.steps.map(\.spokenLabel).joined(separator: String(localized: ", puis ")))
    }
}

/// One step's line: how long, what (and the note under it), at what.
///
/// Strength labels are often long French movement names; they wrap between the two figures
/// rather than widen the drawer past the screen.
private struct PlannedStepLine: View {
    let step: V1PlannedSessionStep
    let hasPictures: Bool

    /// One width for the dose or duration column down the whole table: « 15 min », « 4 × 8 ».
    @ScaledMetric(relativeTo: .callout) private var doseWidth: CGFloat = 64

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let detail = step.detail {
                Text(detail)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .frame(width: doseWidth, alignment: .leading)
            }
            if hasPictures { picture }
            VStack(alignment: .leading, spacing: 2) {
                Text(step.label)
                    .font(SharpitTypography.system(size: 16, weight: step.target == nil ? .regular : .semibold, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let notes = step.notes, !notes.isEmpty {
                    Text(notes)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let target = step.target {
                Text(target)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150, alignment: .trailing)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.spokenLabel)
    }

    /// The exercise's picture, or the same slot with a quiet glyph.
    @ViewBuilder
    private var picture: some View {
        if let thumb = ExerciseMediaCatalog.thumbURL(name: step.label) {
            GuidedExerciseThumbView(url: thumb, size: 40)
        } else {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(SharpitColor.slate.opacity(0.6))
                .frame(width: 40, height: 40)
                .background(SharpitColor.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

private extension V1PlannedSessionStep {
    var spokenLabel: String {
        [label, detail, target, notes].compactMap { $0 }.joined(separator: ", ")
    }
}

#Preview("Endurance") {
    PlannedSessionBreakdownList(
        steps: [
            V1PlannedSessionStep(key: "0-0", label: String(localized: "Échauffement"), detail: String(localized: "15 min"), group: "0"),
            V1PlannedSessionStep(
                key: "1-0",
                label: String(localized: "Bloc"),
                detail: String(localized: "3 min"),
                target: "4:05 – 4:20 /km",
                group: "1",
                repeatCount: 5
            ),
            V1PlannedSessionStep(key: "1-1", label: String(localized: "Récup"), detail: "90 s", group: "1", repeatCount: 5),
            V1PlannedSessionStep(key: "2-0", label: String(localized: "Retour au calme"), detail: String(localized: "10 min"), group: "2"),
        ],
        derived: false
    )
    .padding()
    .background(SharpitCanvasBackground())
}

#Preview("Force / mobilité") {
    PlannedSessionBreakdownList(
        steps: [
            V1PlannedSessionStep(
                key: "strength-0",
                label: String(localized: "Étirements dynamiques hanches et ischio-jambiers unilatéraux"),
                detail: "3 × 45 s"
            ),
            V1PlannedSessionStep(
                key: "strength-1",
                label: String(localized: "Rotation externe d'épaule à la bande élastique"),
                detail: "3 × 12",
                target: String(localized: "Bande légère")
            ),
        ],
        derived: false
    )
    .frame(width: 375)
    .padding()
    .background(SharpitCanvasBackground())
}

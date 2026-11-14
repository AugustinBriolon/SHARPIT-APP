import SwiftUI

/// What a session holds, top to bottom: who and when, its figures and why the coach wrote it,
/// then the session in time — mobility, steps, stretches — and the instruction. Shared by the
/// planned session's drawer and the proposal's page, so both read the same; each screen adds
/// its own actions under the why.
///
/// One panel leads, the steps': the routines fold to a line around them, and the figures and
/// the why sit on the canvas rather than in cards of the same weight.
struct PlannedSessionSummary<Actions: View>: View {
    let preview: PlannedSessionPreview
    let steps: [V1PlannedSessionStep]
    let stepsAreDerived: Bool
    var isLoadingBreakdown = false
    /// Mobility and stretches around the steps (SHARPIT ADR-114), when the session has them.
    var routines: V1SessionRoutines?
    /// Records what the athlete did with a routine; nil where it cannot be said yet.
    var onRoutineStatus: ((V1RoutinePart, V1RoutineStatus?) -> Void)?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            VStack(alignment: .leading, spacing: 20) {
                header
                if !preview.metrics.isEmpty {
                    figures
                }
            }
            actions
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                if let sequence = SessionSequence.of(durationMin: preview.durationMin, routines: routines) {
                    SessionSequenceBar(sequence: sequence)
                        .padding(.bottom, SharpitSpacing.xs)
                }
                if let routines {
                    routinePanel(String(localized: "Mobilité avant"), routines.warmup, .warmup)
                }
                if !steps.isEmpty {
                    PlannedSessionBreakdownList(steps: steps, derived: stepsAreDerived)
                        .padding(.top, SharpitSpacing.xs)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if isLoadingBreakdown {
                    HStack(spacing: SharpitSpacing.xs) {
                        ProgressView()
                        Text("Chargement du déroulé…")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                    }
                }
                if let routines {
                    routinePanel(String(localized: "Étirements ciblés"), routines.cooldown, .cooldown)
                }
            }
            if let rationale = preview.rationale, !rationale.isEmpty {
                words(String(localized: "Pourquoi cette séance"), rationale)
            }
            if let notes = preview.notes, !notes.isEmpty {
                words(String(localized: "Consigne"), notes)
            }
        }
    }

    /// « Clé » when the coach marked it, the sport before the title, then the day.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if preview.isKey {
                CliniqueStatusPill(String(localized: "Clé"), status: .pro)
            }
            Text(PlannedSessionReadout.title(sport: preview.sport, title: preview.title))
                .font(SharpitTypography.system(size: 24, weight: .semibold, relativeTo: .title2, digits: true))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if let date = preview.date {
                Text(date.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The figures between two hairlines, each centred under its label.
    private var figures: some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            HStack(spacing: 0) {
                ForEach(Array(preview.metrics.enumerated()), id: \.element.label) { index, metric in
                    if index > 0 {
                        Rectangle().fill(SharpitColor.divider).frame(width: 1, height: 34)
                    }
                    VStack(spacing: 4) {
                        Text(metric.label)
                            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                            .foregroundStyle(SharpitColor.slate)
                            .lineLimit(1)
                        Text(metric.value)
                            .font(SharpitTypography.system(size: 19, weight: .semibold, relativeTo: .title3, digits: true))
                            .foregroundStyle(SharpitColor.foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 14)
            CliniqueDivider()
        }
    }

    /// The coach's reason, on the canvas under the figures: it is what makes the session his
    /// and the athlete's, so it is read before the steps rather than after them.
    /// A routine with no move — the stretches after a recovery session — leaves no panel.
    @ViewBuilder
    private func routinePanel(_ title: String, _ routine: V1SessionRoutine, _ part: V1RoutinePart) -> some View {
        if !routine.moves.isEmpty {
            SessionRoutinePanel(
                title: title,
                routine: routine,
                onStatus: onRoutineStatus.map { record in { record(part, $0) } }
            )
        }
    }

    /// The coach's reason, or the instruction: a titled paragraph on the sheet, after the steps.
    private func words(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How a planned session words itself.
nonisolated enum PlannedSessionReadout {
    /// « Vélo · Seuil 2 × 12 min »; the title alone when it already names the sport or is it.
    static func title(sport: String, title: String) -> String {
        title.localizedCaseInsensitiveContains(sport) ? title : "\(sport) · \(title)"
    }
}

extension PlannedSessionSummary where Actions == EmptyView {
    init(preview: PlannedSessionPreview) {
        self.init(
            preview: preview, steps: preview.steps, stepsAreDerived: preview.stepsAreDerived,
            routines: preview.routines
        ) { EmptyView() }
    }
}

/// A session the coach proposes, read in full. Pushed inside the generator — one sheet at a
/// time, as the HIG asks.
struct ProposedSessionPage: View {
    let session: V1GeneratedSession
    @Environment(\.isExpertReading) private var isExpertReading

    var body: some View {
        ScrollView {
            PlannedSessionSummary(preview: PlannedSessionPreview(generated: session, isExpertReading: isExpertReading))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, SharpitSpacing.md)
        }
        .cliniqueSheet(wash: .neutral, height: 200)
        .navigationTitle("Séance proposée")
        .navigationBarTitleDisplayMode(.inline)
    }
}

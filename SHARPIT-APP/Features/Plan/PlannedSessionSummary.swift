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

    @State private var isWhyExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                header
                if !preview.metrics.isEmpty {
                    figures
                }
            }
            if let rationale = preview.rationale, !rationale.isEmpty {
                coachWhy(rationale)
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
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if isLoadingBreakdown {
                    HStack(spacing: SharpitSpacing.xs) {
                        ProgressView()
                        Text("Chargement du déroulé…")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                if let routines {
                    routinePanel(String(localized: "Étirements ciblés"), routines.cooldown, .cooldown)
                }
            }
            if let notes = preview.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    SharpitEyebrow(String(localized: "Consigne"))
                    Text(notes)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(spacing: SharpitSpacing.sm) {
                SharpitIconTile(symbol: preview.symbolName)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: SharpitSpacing.xs) {
                        Text(preview.sport)
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)
                        if preview.isKey {
                            SharpitInlineTag(String(localized: "Clé"))
                        }
                    }
                    if let date = preview.date {
                        Text(date.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .lineLimit(1)
                    }
                }
            }
            Text(preview.title)
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The figures on the canvas, each under its label, split by hairlines — a readout, not a card.
    private var figures: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.md) {
            ForEach(Array(preview.metrics.enumerated()), id: \.element.label) { index, metric in
                if index > 0 {
                    Rectangle()
                        .fill(SharpitColor.analysisBorder)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    Text(metric.label)
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                    Text(metric.value)
                        .font(SharpitTypography.data)
                        .tracking(SharpitTypography.dataTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .accessibilityElement(children: .combine)
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
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

    private func coachWhy(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            SharpitEyebrow(String(localized: "Pourquoi cette séance"))
            Text(text)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(isWhyExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .onTapGesture {
            withAnimation(SharpitMotion.reveal) { isWhyExpanded.toggle() }
        }
        .accessibilityElement(children: .combine)
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
                .padding(SharpitSpacing.pageInset)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle("Séance proposée")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

/// What a session holds, top to bottom: its sport and title, its figures, its steps, the
/// instruction and why the coach wrote it. Shared by the planned session's drawer and the
/// proposal's page, so both read the same; each screen adds its own actions under the title.
struct PlannedSessionSummary<Actions: View>: View {
    let preview: PlannedSessionPreview
    let steps: [V1PlannedSessionStep]
    let stepsAreDerived: Bool
    var isLoadingBreakdown = false
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            header
            actions
            if !preview.metrics.isEmpty {
                metricsRow
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
            if let notes = preview.notes, !notes.isEmpty {
                textPanel("Consigne", notes)
            }
            if let rationale = preview.rationale, !rationale.isEmpty {
                textPanel("Pourquoi cette séance", rationale)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: preview.symbolName)
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitSportTone.label(for: preview.sport))
                Text(preview.sport)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer(minLength: 0)
                if let date = preview.date {
                    Text(date.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            Text(preview.title)
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
        }
    }

    private func textPanel(_ eyebrow: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(eyebrow)
            Text(text)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.md) {
            ForEach(preview.metrics, id: \.label) { metric in
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    Text(metric.label)
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Text(metric.value)
                        .font(SharpitTypography.data)
                        .tracking(SharpitTypography.dataTracking)
                        .foregroundStyle(SharpitColor.foreground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

extension PlannedSessionSummary where Actions == EmptyView {
    init(preview: PlannedSessionPreview) {
        self.init(preview: preview, steps: preview.steps, stepsAreDerived: preview.stepsAreDerived) { EmptyView() }
    }
}

/// A session the coach proposes, read in full. Pushed inside the generator — one sheet at a
/// time, as the HIG asks — and zoomed from its row.
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

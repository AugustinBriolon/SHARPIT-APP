import SwiftUI

/// What a planned session holds, in a sheet.
///
/// A planned session has no detail screen to open — there is nothing recorded yet, only
/// an intention. A drawer says what is prescribed and offers the one action that makes
/// sense before it happens: asking the coach about it.
struct PlannedSessionDrawer: View {
    let session: V1PlannedSessionItem
    let onDiscussWithCoach: (CoachDiscussContext) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    header
                    if !metrics.isEmpty {
                        metricsRow
                    }
                    if let notes = session.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                            SharpitEyebrow("Consigne")
                            Text(notes)
                                .font(SharpitTypography.body)
                                .foregroundStyle(SharpitColor.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SharpitSpacing.cardPadding)
                        .sharpitSurface(.panel)
                    }
                    CoachDiscussButton(title: "Discuter avec le coach") {
                        onDiscussWithCoach(
                            CoachDiscuss.describe(
                                .plannedSession(sessionId: session.id),
                                name: session.title ?? session.displayType
                            )
                        )
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.pageInset)
            }
            .background(SharpitCanvasBackground())
            .navigationTitle("Séance prévue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: session.symbolName)
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitSportTone.accent(for: session.displayType))
                Text(session.displayType)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer(minLength: 0)
                Text(session.date.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Text(session.title ?? session.displayType)
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
        }
    }

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.md) {
            ForEach(metrics, id: \.label) { metric in
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

    /// Charge/TSS is deliberately absent — it is a planning number, not something the
    /// athlete acts on before a session.
    private var metrics: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        if let durationMin = session.durationMin {
            rows.append(("Durée", "\(durationMin) min"))
        }
        if let intensity = session.intensity, !intensity.isEmpty {
            rows.append(("Intensité", intensity.capitalized))
        }
        return rows
    }
}

/// The button that hands a subject to the coach.
///
/// It appears wherever the athlete might want to ask about what they are looking at. What
/// travels is a tag naming the subject, never a prefilled question.
struct CoachDiscussButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(SharpitTypography.label)
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(SharpitTypography.label)
            }
            .foregroundStyle(SharpitColor.primaryForeground)
            .padding(.horizontal, SharpitSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                SharpitColor.primary,
                in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

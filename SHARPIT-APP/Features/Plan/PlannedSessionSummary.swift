import SwiftUI

/// What a session holds, top to bottom: who and when, its figures, what the forecast asks, its steps, then why the coach
/// wrote it. Mobility and stretches live in their own drawer (`SessionRoutinesSheet`). Shared by the
/// planned session's drawer and the proposal's page, so both read the same; each screen adds
/// its own actions under the why.
///
struct PlannedSessionSummary<Actions: View>: View {
    let preview: PlannedSessionPreview
    let steps: [V1PlannedSessionStep]
    let stepsAreDerived: Bool
    var isLoadingBreakdown = false
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
            if !preview.conditions.isEmpty {
                SessionConditionsSection(advisories: preview.conditions)
            }
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
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
            }
            if let rationale = preview.rationale, !rationale.isEmpty {
                words(String(localized: "Pourquoi cette séance"), rationale)
            }
            // No « Consigne »: the déroulé already says what to do, step by step.
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

    /// The coach's reason: a titled paragraph on the sheet, after the steps.
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
            preview: preview, steps: preview.steps, stepsAreDerived: preview.stepsAreDerived
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

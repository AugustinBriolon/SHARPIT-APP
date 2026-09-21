import SwiftUI

// MARK: - Tiles on the detail page

/// A half-width readout that opens a drawer: a caption with a chevron on top, the value
/// below. Both tiles of a row stretch to the taller one.
private struct ReadoutTile<Value: View>: View {
    let caption: String
    let action: () -> Void
    @ViewBuilder let value: Value

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                HStack(spacing: SharpitSpacing.xxs) {
                    Text(caption)
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .accessibilityHidden(true)
                }
                value
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Effort and feeling are one answer — "how did it go" — so they share one tile and one
/// drawer. Unrated, the value becomes the invitation to rate.
struct SessionFeedbackTile: View {
    let rpe: Int?
    let feeling: SessionFeeling?
    let accent: Color
    let action: () -> Void

    var body: some View {
        ReadoutTile(caption: "Effort · Ressenti", action: action) {
            if rpe == nil && feeling == nil {
                Label("Noter", systemImage: "plus.circle.fill")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(accent)
                    .symbolEffect(.bounce, options: .nonRepeating)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.md) {
                    ScaleReadout(
                        value: rpe,
                        outOf: 10,
                        tone: rpe.map(SessionFeedbackTone.effort) ?? SharpitColor.mutedForeground
                    )
                    ScaleReadout(
                        value: feeling?.rawValue,
                        outOf: 5,
                        tone: feeling.map(SessionFeedbackTone.feeling) ?? SharpitColor.mutedForeground
                    )
                }
            }
        }
        .accessibilityHint("Ouvre l'évaluation de la séance")
    }
}

private struct ScaleReadout: View {
    let value: Int?
    let outOf: Int
    let tone: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value.map(String.init) ?? "—")
                .font(SharpitTypography.gaugeScore)
                .tracking(SharpitTypography.gaugeScoreTracking)
                .foregroundStyle(tone)
                .contentTransition(.numericText())
            Text("/\(outOf)")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
    }
}

struct ComplianceTile: View {
    let analysis: V1PlannedSessionAnalysis
    let action: () -> Void

    private var verdict: SessionVerdict? { analysis.verdict.flatMap(SessionVerdict.init(rawValue:)) }
    private var tone: Color {
        analysis.complianceScore.map(SessionFeedbackTone.compliance) ?? verdict?.tone ?? SharpitColor.signalNeutral
    }

    var body: some View {
        ReadoutTile(caption: "Conformité", action: action) {
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(analysis.complianceScore.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(SharpitTypography.gaugeScore)
                        .tracking(SharpitTypography.gaugeScoreTracking)
                        .foregroundStyle(tone)
                    Text("%")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                if let verdict {
                    Label(verdict.label, systemImage: verdict.symbolName)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(verdict.tone)
                        .lineLimit(2)
                }
            }
        }
    }
}

// MARK: - Effort and feeling drawer

/// Two scales, no buttons: each tap saves. Closing the drawer writes anything still pending.
struct SubjectiveEditorSheet: View {
    @Bindable var store: ActivitySubjectiveStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    scale(
                        title: "Effort perçu",
                        value: store.rpe,
                        outOf: 10,
                        caption: "1 très facile · 10 maximal",
                        tone: store.rpe.map(SessionFeedbackTone.effort)
                    ) {
                        RatingGrid(
                            values: Array(1...10),
                            selection: store.rpe,
                            tone: SessionFeedbackTone.effort
                        ) { store.setRPE($0) }
                    }

                    scale(
                        title: "Ressenti",
                        value: store.feeling?.rawValue,
                        outOf: 5,
                        caption: store.feeling?.hint ?? "1 très mal · 5 très bien",
                        tone: store.feeling.map(SessionFeedbackTone.feeling)
                    ) {
                        RatingGrid(
                            values: SessionFeeling.allCases.map(\.rawValue),
                            selection: store.feeling?.rawValue,
                            tone: { SessionFeedbackTone.feeling(SessionFeeling(rawValue: $0) ?? .okay) }
                        ) { raw in
                            if let feeling = SessionFeeling(rawValue: raw) { store.setFeeling(feeling) }
                        }
                    }

                    SaveStatusLine(status: store.status)
                }
                .padding(SharpitSpacing.pageInset)
            }
            .navigationTitle("Comment s'est passée la séance ?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear { Task { await store.flush() } }
    }

    private func scale<Grid: View>(
        title: String,
        value: Int?,
        outOf: Int,
        caption: String,
        tone: Color?,
        @ViewBuilder grid: () -> Grid
    ) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .lastTextBaseline) {
                SharpitEyebrow(title)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value.map(String.init) ?? "—")
                        .font(SharpitTypography.gaugeScore)
                        .foregroundStyle(tone ?? SharpitColor.mutedForeground)
                        .contentTransition(.numericText())
                    Text("/\(outOf)")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            grid()
            Text(caption)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .contentTransition(.opacity)
        }
        .animation(SharpitMotion.selection, value: value)
    }
}

private struct SaveStatusLine: View {
    let status: ActivitySubjectiveStore.Status

    var body: some View {
        Group {
            switch status {
            case .idle:
                Text("Chaque touche est enregistrée.")
                    .foregroundStyle(SharpitColor.mutedForeground)
            case .saving:
                Label("Enregistrement…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(SharpitColor.mutedForeground)
            case .saved:
                Label("Enregistré", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(SharpitColor.signalRecovery)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(SharpitColor.signalCaution)
            }
        }
        .font(SharpitTypography.meta)
        .frame(maxWidth: .infinity, alignment: .center)
        .contentTransition(.opacity)
        .animation(SharpitMotion.fade, value: status)
    }
}

/// A row of numbered steps. The selected one fills with its own tone, so the scale reads
/// as a ramp and not as a column of identical buttons.
private struct RatingGrid: View {
    let values: [Int]
    let selection: Int?
    let tone: (Int) -> Color
    let onSelect: (Int) -> Void

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 0), spacing: SharpitSpacing.xs),
                count: min(values.count, 5)
            ),
            spacing: SharpitSpacing.xs
        ) {
            ForEach(values, id: \.self) { value in
                let isSelected = selection == value
                Button { onSelect(value) } label: {
                    Text("\(value)")
                        .font(SharpitTypography.data)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(isSelected ? Color.white : SharpitColor.foreground)
                        .background {
                            RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                                .fill(isSelected ? tone(value) : SharpitElevatedColor.panelOnSheet)
                                .sharpitShadow(.control)
                        }
                        .overlay(alignment: .bottom) {
                            if !isSelected {
                                Capsule()
                                    .fill(tone(value))
                                    .frame(width: 14, height: 3)
                                    .padding(.bottom, 7)
                            }
                        }
                        .scaleEffect(isSelected ? 1.04 : 1)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(SharpitMotion.selection, value: selection)
    }
}

// MARK: - Compliance drawer

struct ComplianceDetailSheet: View {
    let title: String
    let analysis: V1PlannedSessionAnalysis

    private var verdict: SessionVerdict? { analysis.verdict.flatMap(SessionVerdict.init(rawValue:)) }
    private var tone: Color {
        analysis.complianceScore.map(SessionFeedbackTone.compliance) ?? verdict?.tone ?? SharpitColor.signalNeutral
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    header

                    if let summary = analysis.summary, !summary.isEmpty {
                        Text(summary)
                            .font(SharpitTypography.cardTitle)
                            .tracking(SharpitTypography.cardTitleTracking)
                            .foregroundStyle(SharpitColor.foreground)
                            .lineSpacing(3)
                    }

                    if let remarks = analysis.remarks, !remarks.isEmpty {
                        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                            SharpitEyebrow("Ce que montrent les données")
                            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                                ForEach(remarks, id: \.self) { remark in
                                    HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                                        Circle()
                                            .fill(tone)
                                            .frame(width: 7, height: 7)
                                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                                        Text(remark)
                                            .font(SharpitTypography.body)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(SharpitSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .sharpitSurface(.panel)
                        }
                    }

                    if let recommendation = analysis.recommendation, !recommendation.isEmpty {
                        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                            Image(systemName: "arrow.forward.circle.fill")
                                .font(.title3)
                                .foregroundStyle(SharpitColor.primary)
                            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                                SharpitEyebrow("Pour la suite")
                                Text(recommendation)
                                    .font(SharpitTypography.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(SharpitSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            SharpitColor.primary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                        )
                    }
                }
                .padding(SharpitSpacing.pageInset)
            }
            .navigationTitle("Conformité au plan")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        HStack(spacing: SharpitSpacing.md) {
            ZStack {
                SharpitScoreRing(
                    fraction: (analysis.complianceScore ?? 0) / 100,
                    tone: tone,
                    lineWidth: 7
                )
                VStack(spacing: 0) {
                    Text(analysis.complianceScore.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(SharpitTypography.gaugeScore)
                        .foregroundStyle(tone)
                    Text("%")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                Text(title)
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                if let verdict {
                    Label(verdict.label, systemImage: verdict.symbolName)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(verdict.tone)
                        .padding(.horizontal, SharpitSpacing.sm)
                        .padding(.vertical, SharpitSpacing.xxs + 2)
                        .background(verdict.tone.opacity(0.14), in: Capsule())
                }
            }
        }
    }
}

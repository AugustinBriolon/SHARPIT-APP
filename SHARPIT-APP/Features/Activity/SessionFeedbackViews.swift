import SwiftUI

// MARK: - Tiles on the detail page

/// A half-width readout that opens a drawer: a caption with a chevron on top, the value
/// below. Both tiles of a row stretch to the taller one.
struct ReadoutTile<Value: View>: View {
    let caption: String
    let action: () -> Void
    @ViewBuilder let value: Value

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                ReadoutTileCaption(caption) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .accessibilityHidden(true)
                }
                value
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .padding(SharpitSpacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A half-width tile's title: sentence case and ink, like a card header without its tile.
struct ReadoutTileCaption<Trailing: View>: View {
    let caption: String
    @ViewBuilder let trailing: Trailing

    init(_ caption: String, @ViewBuilder trailing: () -> Trailing) {
        self.caption = caption
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: SharpitSpacing.xxs) {
            Text(caption)
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            trailing
        }
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
        ReadoutTile(caption: String(localized: "Effort · Ressenti"), action: action) {
            if rpe == nil && feeling == nil {
                Label("Noter", systemImage: "plus.circle.fill")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(accent)
                    .symbolEffect(.bounce, options: .nonRepeating)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.md) {
                    ScaleReadout(value: rpe, outOf: 10)
                    ScaleReadout(value: feeling?.rawValue, outOf: 5)
                }
            }
        }
        .accessibilityHint("Ouvre l'évaluation de la séance")
    }
}

/// A figure on its scale, in ink; the scale's ramp lives in the drawer's grid, not in the type.
struct ScaleReadout: View {
    let value: Int?
    let outOf: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value.map(String.init) ?? "—")
                .font(SharpitTypography.gaugeScore)
                .tracking(SharpitTypography.gaugeScoreTracking)
                .foregroundStyle(value == nil ? SharpitColor.mutedForeground : SharpitColor.foreground)
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
        ReadoutTile(caption: String(localized: "Conformité"), action: action) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(analysis.complianceScore.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(SharpitTypography.gaugeScore)
                        .tracking(SharpitTypography.gaugeScoreTracking)
                        .foregroundStyle(tone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("%")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                if let verdict {
                    SharpitPill(verdict.label, style: verdict == .asPlanned ? .lime : .neutral)
                }
            }
        }
    }
}

/// A matching tile shown when a planned session is linked to the activity, but the compliance
/// analysis calculation has not finished yet.
struct CompliancePendingTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            ReadoutTileCaption(String(localized: "Conformité")) {
                Image(systemName: "hourglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .center, spacing: SharpitSpacing.xs) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(SharpitColor.mutedForeground)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Calcul en cours…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                    Text("Séance planifiée")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(SharpitSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conformité : Calcul en cours")
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
                    SubjectiveScale(
                        title: String(localized: "Effort perçu"),
                        value: store.rpe,
                        outOf: 10,
                        caption: String(localized: "1 très facile · 10 maximal"),
                        tone: store.rpe.map(SessionFeedbackTone.effort)
                    ) {
                        RatingGrid(
                            values: Array(1...10),
                            selection: store.rpe,
                            tone: SessionFeedbackTone.effort
                        ) { store.setRPE($0) }
                    }

                    SubjectiveScale(
                        title: String(localized: "Ressenti"),
                        value: store.feeling?.rawValue,
                        outOf: 5,
                        caption: store.feeling?.hint ?? String(localized: "1 très mal · 5 très bien"),
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
}

/// One titled scale: its value read large on the right, the grid, a caption that reads the choice.
struct SubjectiveScale<Grid: View>: View {
    let title: String
    let value: Int?
    let outOf: Int
    let caption: String
    let tone: Color?
    @ViewBuilder let grid: Grid

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .lastTextBaseline) {
                SharpitEyebrow(title)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value.map(String.init) ?? "—")
                        .font(SharpitTypography.gaugeScore)
                        .foregroundStyle(tone == nil ? SharpitColor.mutedForeground : SharpitColor.foreground)
                        .contentTransition(.numericText())
                    Text("/\(outOf)")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            grid
            Text(caption)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .contentTransition(.opacity)
        }
        .animation(SharpitMotion.selection, value: value)
    }
}

struct SaveStatusLine: View {
    let status: SubjectiveSaveStatus

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
                    .foregroundStyle(SharpitColor.foreground)
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
struct RatingGrid: View {
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
                        .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
                        .background {
                            RoundedRectangle(cornerRadius: SharpitRadius.control, style: .continuous)
                                .fill(isSelected ? SharpitColor.primary : SharpitElevatedColor.panelOnSheet)
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
                .accessibilityLabel("\(value) sur \(values.count)")
                .accessibilityValue(isSelected ? String(localized: "Sélectionné") : String(localized: "Non sélectionné"))
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
    /// Takes the activity off its planned session — a wrong match; nil where it cannot.
    var onUnlink: (() -> Void)?
    var onReanalyze: (() -> Void)?

    @State private var isConfirmingUnlink = false

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

                    if let strengths = analysis.strengths, !strengths.isEmpty {
                        AnalysisBulletBlock(title: String(localized: "Forces"), items: strengths, tone: SharpitColor.foreground)
                    }

                    if let improvements = analysis.improvements, !improvements.isEmpty {
                        AnalysisBulletBlock(title: String(localized: "À travailler"), items: improvements, tone: SharpitColor.signalCaution)
                    }

                    if let tags = analysis.scoreTags, !tags.isEmpty {
                        Text(tags.map(SessionAnalysisScoreTagLabel.fr).joined(separator: " · "))
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }

                    if let remarks = analysis.remarks, !remarks.isEmpty {
                        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                            SharpitEyebrow(String(localized: "Ce que montrent les données"))
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
                                SharpitEyebrow(String(localized: "Pour la suite"))
                                Text(recommendation)
                                    .font(SharpitTypography.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(SharpitSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .sharpitContainerCorner(SharpitRadius.panel)
                        .background(
                            SharpitColor.primary.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                        )
                    }

                    if let reassessments = analysis.physicalReassessments, !reassessments.isEmpty {
                        AnalysisBulletBlock(
                            title: String(localized: "Zones à réévaluer"),
                            items: reassessments.map { item in
                                "\(item.noteTitle) — \(item.question)"
                            },
                            tone: SharpitColor.signalCaution
                        )
                        Text("Parle au coach pour Continuer, Alléger, Reporter ou Pause.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                .padding(SharpitSpacing.pageInset)
            }
            .navigationTitle("Conformité au plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onUnlink != nil || onReanalyze != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if let onReanalyze {
                                Button("Réanalyser", systemImage: "arrow.clockwise", action: onReanalyze)
                            }
                            if onUnlink != nil {
                                Divider()
                                Button(role: .destructive) { isConfirmingUnlink = true } label: {
                                    Label("Délier de la séance prévue", systemImage: "link.badge.minus")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("Actions de la séance prévue")
                    }
                }
            }
            .confirmationDialog(
                String(localized: "Délier cette activité ?"),
                isPresented: $isConfirmingUnlink,
                titleVisibility: .visible
            ) {
                Button("Délier", role: .destructive) { onUnlink?() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("« \(title) » redevient à faire dans ton plan, et cette analyse disparaît.")
            }
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

private struct AnalysisBulletBlock: View {
    let title: String
    let items: [String]
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(title)
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                        Circle()
                            .fill(tone)
                            .frame(width: 7, height: 7)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(item)
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
}

private enum SessionAnalysisScoreTagLabel {
    static func fr(_ raw: String) -> String {
        switch raw {
        case "PACING": return String(localized: "Allure")
        case "INTENSITY": return String(localized: "Intensité")
        case "VOLUME": return String(localized: "Volume")
        case "EXECUTION": return String(localized: "Exécution")
        case "RECOVERY": return String(localized: "Récupération")
        case "TECHNIQUE": return String(localized: "Technique")
        case "FUELING": return String(localized: "Nutrition")
        case "CONSISTENCY": return String(localized: "Régularité")
        default: return raw
        }
    }
}

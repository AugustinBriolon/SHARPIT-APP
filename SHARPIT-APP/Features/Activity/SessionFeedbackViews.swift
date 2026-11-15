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
                        .foregroundStyle(SharpitColor.slate)
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

/// A figure on its scale, in ink; the scale's ramp lives in the drawer's grid, not in the type.
struct ScaleReadout: View {
    let value: Int?
    let outOf: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(value.map(String.init) ?? "—")
                .font(SharpitTypography.gaugeScore)
                .tracking(SharpitTypography.gaugeScoreTracking)
                .foregroundStyle(value == nil ? SharpitColor.slate : SharpitColor.foreground)
                .contentTransition(.numericText())
            Text("/\(outOf)")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
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
                    .foregroundStyle(SharpitColor.slate)
                    .symbolEffect(.pulse)
                    .accessibilityHidden(true)
            }
            HStack(alignment: .center, spacing: SharpitSpacing.xs) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(SharpitColor.slate)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Calcul en cours…")
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                    Text("Séance planifiée")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
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

/// Two scales, no buttons: each answer saves. Closing the drawer writes anything still pending.
struct SubjectiveEditorSheet: View {
    @Bindable var store: ActivitySubjectiveStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CliniqueSheetTitle(String(localized: "Comment s'est passée la séance ?"))
                .padding(.bottom, 22)
            CliniqueScale(
                title: String(localized: "Effort perçu"),
                values: Array(1...10),
                selection: store.rpe,
                word: SessionEffortReadout.word,
                ends: (String(localized: "Très facile"), String(localized: "Maximal"))
            ) { store.setRPE($0) }
            CliniqueDivider().padding(.vertical, 18)
            CliniqueScale(
                title: String(localized: "Ressenti"),
                values: SessionFeeling.allCases.map(\.rawValue),
                selection: store.feeling?.rawValue,
                word: { SessionFeeling(rawValue: $0)?.storedValue },
                ends: (SessionFeeling.veryBad.storedValue, SessionFeeling.veryGood.storedValue)
            ) { raw in
                if let feeling = SessionFeeling(rawValue: raw) { store.setFeeling(feeling) }
            }
            if let hint = store.feeling?.hint {
                Text(hint)
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            Spacer(minLength: SharpitSpacing.md)
            SaveStatusLine(status: store.status)
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, SharpitSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        .onDisappear { Task { await store.flush() } }
    }
}

nonisolated enum SessionEffortReadout {
    /// The word a perceived effort stands for, on the 1–10 scale.
    static func word(_ rpe: Int) -> String? {
        switch rpe {
        case 1: String(localized: "Très facile")
        case 2...3: String(localized: "Facile")
        case 4...5: String(localized: "Modéré")
        case 6: String(localized: "Soutenu")
        case 7...8: String(localized: "Dur")
        case 9: String(localized: "Très dur")
        case 10: String(localized: "Maximal")
        default: nil
        }
    }
}

struct SaveStatusLine: View {
    let status: SubjectiveSaveStatus

    var body: some View {
        Group {
            switch status {
            case .idle:
                Text("Chaque touche est enregistrée.")
                    .foregroundStyle(SharpitColor.slate)
            case .saving:
                Label("Enregistrement…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(SharpitColor.slate)
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

// MARK: - Compliance drawer

struct ComplianceDetailSheet: View {
    let title: String
    let analysis: V1PlannedSessionAnalysis
    /// Takes the activity off its planned session — a wrong match; nil where it cannot.
    var onUnlink: (() -> Void)?
    var onReanalyze: (() -> Void)?

    /// Opens the coach on this session; nil where the coach cannot be reached from here.
    var onDiscuss: (() -> Void)?

    @State private var isConfirmingUnlink = false
    @Environment(\.dismiss) private var dismiss

    private var verdict: SessionVerdict? { analysis.verdict.flatMap(SessionVerdict.init(rawValue:)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CliniqueSheetTitle(String(localized: "Conformité au plan"))
                    .padding(.bottom, 14)
                header
                if let summary = analysis.summary, !summary.isEmpty {
                    Text(summary)
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.foreground)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                if let strengths = analysis.strengths, !strengths.isEmpty {
                    AnalysisLines(title: String(localized: "Ce qui est tenu"), items: strengths)
                }
                if let improvements = analysis.improvements, !improvements.isEmpty {
                    AnalysisLines(title: String(localized: "À travailler"), items: improvements)
                }
                if let remarks = analysis.remarks, !remarks.isEmpty {
                    AnalysisLines(title: String(localized: "Ce que montrent les données"), items: remarks)
                }
                if let reassessments = analysis.physicalReassessments, !reassessments.isEmpty {
                    AnalysisLines(
                        title: String(localized: "Zones à réévaluer"),
                        items: reassessments.map { "\($0.noteTitle) — \($0.question)" }
                    )
                }
                if let tags = analysis.scoreTags, !tags.isEmpty {
                    Text(tags.map(SessionAnalysisScoreTagLabel.fr).joined(separator: " · "))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .padding(.top, 14)
                }
                if let recommendation = analysis.recommendation, !recommendation.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pour la suite")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.slate)
                        Text(recommendation)
                            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(SharpitColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .cliniqueCard()
                    .padding(.top, 18)
                }
                if onUnlink != nil {
                    Button(role: .destructive) { isConfirmingUnlink = true } label: {
                        Text("Délier de la séance prévue").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CliniqueButtonStyle(kind: .plain))
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, SharpitSpacing.md)
        }
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        // Docked, as on the mock-up: the coach first, the new reading beside it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if onDiscuss != nil || onReanalyze != nil {
                HStack(spacing: 8) {
                    if let onDiscuss {
                        Button(action: onDiscuss) { Text("En parler au coach").frame(maxWidth: .infinity) }
                            .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                    }
                    if let onReanalyze {
                        Button("Réanalyser", action: onReanalyze)
                            .buttonStyle(CliniqueButtonStyle(kind: .outline))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, SharpitSpacing.xs)
                .background(SharpitColor.card)
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

    /// The session it was read against, then the score big beside the verdict as a pill.
    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text(title)
                .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(analysis.complianceScore.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(SharpitTypography.system(size: 46, weight: .semibold, relativeTo: .largeTitle, digits: true))
                        .tracking(-1.2)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("/ 100")
                        .font(SharpitTypography.system(size: 18, weight: .regular, relativeTo: .title3))
                        .foregroundStyle(SharpitColor.slate)
                }
                if let verdict {
                    CliniqueStatusPill(verdict.label, status: ActivitySheetReadout.status(verdict))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// A titled run of the coach's sentences, each on its own line of the sheet.
private struct AnalysisLines: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 26)
                .padding(.bottom, 6)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { CliniqueDivider() }
                Text(item)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 13)
            }
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

import SwiftUI

/// The words and symbols the score is read with. The server words the reasons; the app only
/// chooses how they look (SHARPIT ADR-063).
nonisolated enum FoodHealthPresentation {
    static func gradeTone(_ grade: V1FoodHealth.Grade?) -> Color {
        switch grade {
        case .excellent: SharpitColor.signalRecovery
        case .good: SharpitColor.foreground
        case .mediocre: SharpitColor.signalCaution
        case .poor: SharpitColor.signalRisk
        case nil: SharpitColor.mutedForeground
        }
    }

    static func highlightTone(_ tone: V1FoodHealth.Highlight.Tone) -> Color {
        switch tone {
        case .negative: SharpitColor.signalRisk
        case .positive: SharpitColor.signalRecovery
        case .neutral: SharpitColor.signalNeutral
        }
    }

    static func dietTone(_ status: V1FoodHealth.DietFit.Status) -> Color {
        switch status {
        case .compatible: SharpitColor.signalRecovery
        case .uncertain: SharpitColor.mutedForeground
        case .incompatible: SharpitColor.signalRisk
        }
    }

    static func dietSymbol(_ status: V1FoodHealth.DietFit.Status) -> String {
        switch status {
        case .compatible: "checkmark.circle"
        case .uncertain: "questionmark.circle"
        case .incompatible: "xmark.circle"
        }
    }

    /// A symbol per reason; an unknown key falls back on its tone.
    static func symbol(for highlight: V1FoodHealth.Highlight) -> String {
        let prefix = highlight.key.split(separator: "_").first.map(String.init) ?? highlight.key
        switch prefix {
        case "sugars": return "cube"
        case "salt": return "aqi.low"
        case "saturatedFat": return "drop"
        case "protein": return "dumbbell"
        case "fiber": return "leaf"
        case "ultra", "unprocessed": return "gearshape.2"
        case "additives", "additive": return "flask"
        case "energy": return "flame"
        case "sports": return "figure.run"
        default:
            switch highlight.tone {
            case .negative: return "exclamationmark.circle"
            case .positive: return "checkmark.circle"
            case .neutral: return "info.circle"
            }
        }
    }

    /// Under the grade: how many things to watch, how many strengths, one line each.
    static func verdict(_ health: V1FoodHealth) -> String {
        let watch = health.watchPoints.count
        let strengths = health.strengths.count
        switch (watch, strengths) {
        case (0, 0): return "Rien de marquant dans sa composition"
        case (0, _): return strengths == 1 ? "1 point fort, rien à surveiller" : "\(strengths) points forts, rien à surveiller"
        case (_, 0): return watch == 1 ? "1 point à surveiller" : "\(watch) points à surveiller"
        default:
            let watchText = watch == 1 ? "1 point à surveiller" : "\(watch) points à surveiller"
            let strengthText = strengths == 1 ? "1 point fort" : "\(strengths) points forts"
            return "\(watchText)\n\(strengthText)"
        }
    }

    /// Where the grade comes from: « Nutri-Score C (estimé) · NOVA 4 ».
    static func sources(_ health: V1FoodHealth) -> String? {
        var parts: [String] = []
        if let letter = health.nutriScore?.uppercased() {
            parts.append(health.nutriScoreEstimated ? "Nutri-Score \(letter) (estimé)" : "Nutri-Score \(letter)")
        }
        if let nova = health.nova { parts.append("NOVA \(nova)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What the additive section says when the list itself is not there.
    static func additiveStatus(_ health: V1FoodHealth, isCompleting: Bool) -> String? {
        switch health.additivesKnown {
        case .list:
            return nil
        case .count:
            let count = health.additiveCount ?? 0
            let counted = count == 1 ? "1 additif" : "\(count) additifs"
            return isCompleting ? "\(counted), lecture du détail…" : "\(counted), détail indisponible"
        case .unknown:
            return "Ingrédients non renseignés : additifs inconnus"
        }
    }

    static let method = "Nutrition 60 % (Nutri-Score), transformation 20 % (NOVA), additifs 20 %. Un additif à risque plafonne la note à 49. Une information manquante compte pour moitié."
    static let partialMethod = "Aliment saisi à la main : seule l'étiquette nutritionnelle est notée."
    static let disclaimer = "Indicateur Sharpit, pas un avis médical."
}

/// Compact Sharpit score for lists: the number when known, a dash when the product has none.
struct FoodHealthBadge: View {
    let score: Int?
    let grade: V1FoodHealth.Grade?

    init(health: V1FoodHealth?) {
        score = health?.score
        grade = health?.grade
    }

    /// A meal's or a day's score (SHARPIT ADR-070), on the food scale.
    init(meal: V1MealHealth?) {
        score = meal?.score
        grade = meal?.grade
    }

    /// A tinted capsule read as a disabled control; a ring filled to the score reads as a measure.
    /// Static on purpose: rows scroll in and out, and a ring sweeping each time is noise.
    var body: some View {
        HStack(spacing: 5) {
            if let score {
                ZStack {
                    Circle()
                        .stroke(SharpitColor.analysisGrid, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: min(max(Double(score) / 100, 0), 1))
                        .stroke(tone, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 15, height: 15)
            }
            Text(label)
                .font(SharpitTypography.instrument)
                .monospacedDigit()
                .foregroundStyle(tone)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var label: String {
        guard let score else { return "—" }
        return "\(score)"
    }

    private var tone: Color { FoodHealthPresentation.gradeTone(grade) }

    private var accessibility: String {
        if let score, let grade {
            return "Score Sharpit \(score), \(grade.label)"
        }
        return "Score Sharpit indisponible"
    }
}

/// What a meal's score rests on, as the server words it: the grade, then each reason.
struct MealHealthSection: View {
    let health: V1MealHealth

    var body: some View {
        Section {
            HStack(spacing: SharpitSpacing.sm) {
                FoodHealthBadge(meal: health)
                Text(health.grade?.label ?? "Non noté")
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(FoodHealthPresentation.gradeTone(health.grade))
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            ForEach(health.highlights) { FoodHighlightRow(highlight: $0) }
        } header: {
            SharpitEyebrow("Note du repas")
        } footer: {
            SharpitListFooter("Moyenne des scores des aliments, pondérée par leur énergie. \(FoodHealthPresentation.disclaimer)")
        }
        .sharpitListRows()
    }
}

/// Under a food in a list: the declared diets it breaks, so a search answers « can I eat it ».
struct FoodDietConflictLine: View {
    let health: V1FoodHealth?

    var body: some View {
        if let conflicts = health?.incompatibleDiets, !conflicts.isEmpty {
            Label(
                "Hors régime : \(conflicts.map(\.label).joined(separator: ", "))",
                systemImage: "xmark.circle"
            )
            .font(SharpitTypography.meta)
            .foregroundStyle(SharpitColor.signalRisk)
            .lineLimit(1)
        }
    }
}

/// The full reading as list sections: the score and its verdict, the diets, what to watch, the
/// strengths, the additives, and how it is computed. Placed inside a `List`. A page that already
/// shows `FoodHealthScoreHeader` at its top leaves the score out here.
struct FoodHealthSections: View {
    let health: V1FoodHealth
    /// The product is being read by barcode to complete a search hit's additives.
    var isCompleting = false
    var showsScoreHeader = true

    var body: some View {
        if showsScoreHeader || !health.notes.isEmpty {
            Section {
                if showsScoreHeader { FoodHealthScoreHeader(health: health) }
                ForEach(health.notes) { FoodHighlightRow(highlight: $0) }
            } header: {
                SharpitEyebrow("Score Sharpit")
            }
            .sharpitListRows()
        }

        if !health.dietFit.isEmpty {
            Section {
                ForEach(health.dietFit) { FoodDietFitRow(fit: $0) }
            } header: {
                SharpitEyebrow("Mon régime")
            }
            .sharpitListRows()
        }

        if !health.watchPoints.isEmpty {
            Section {
                ForEach(health.watchPoints) { FoodHighlightRow(highlight: $0) }
            } header: {
                SharpitEyebrow("À surveiller")
            }
            .sharpitListRows()
        }

        if !health.strengths.isEmpty {
            Section {
                ForEach(health.strengths) { FoodHighlightRow(highlight: $0) }
            } header: {
                SharpitEyebrow("Points forts")
            }
            .sharpitListRows()
        }

        Section {
            FoodAdditivesRow(health: health, isCompleting: isCompleting)
            FoodHealthMethodRow(isPartial: health.coverage == .partial)
        } footer: {
            SharpitListFooter(FoodHealthPresentation.disclaimer)
        }
        .sharpitListRows()
    }
}

/// The dial with the score, the grade in its tone, the verdict and where the grade comes from.
struct FoodHealthScoreHeader: View {
    let health: V1FoodHealth

    @ScaledMetric(relativeTo: .title) private var dialWidth: CGFloat = 112

    var body: some View {
        HStack(spacing: SharpitSpacing.md) {
            ZStack {
                SharpitTickGauge(score: health.score.map { CGFloat($0) })
                    .frame(width: dialWidth)
                    .aspectRatio(SharpitTickGaugeGeometry.aspectRatio, contentMode: .fit)
                Text(health.score.map(String.init) ?? "—")
                    .font(SharpitTypography.gaugeScore)
                    .tracking(SharpitTypography.gaugeScoreTracking)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)
                    .offset(y: dialWidth * 0.12)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(health.grade?.label ?? "Non noté")
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(FoodHealthPresentation.gradeTone(health.grade))
                Text(FoodHealthPresentation.verdict(health))
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let sources = FoodHealthPresentation.sources(health) {
                    Text(sources)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, SharpitSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        let score = health.score.map { "Score Sharpit \($0) sur 100" } ?? "Score Sharpit indisponible"
        let grade = health.grade.map { ", \($0.label)" } ?? ""
        return "\(score)\(grade). \(FoodHealthPresentation.verdict(health))"
    }
}

/// One reason: its symbol in the reason's tone, the words, the amount on the right.
struct FoodHighlightRow: View {
    let highlight: V1FoodHealth.Highlight

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Image(systemName: FoodHealthPresentation.symbol(for: highlight))
                .foregroundStyle(FoodHealthPresentation.highlightTone(highlight.tone))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.label)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                if let detail = highlight.detail, !isAmount {
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            Spacer(minLength: SharpitSpacing.xs)
            if let detail = highlight.detail, isAmount {
                Text(detail)
                    .font(SharpitTypography.meta)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// « 2,1 g/100 g » reads as a figure on the right; a sentence goes under the label.
    private var isAmount: Bool { (highlight.detail?.count ?? 0) <= 18 }
}

/// One declared diet: compatible, uncertain or not, and why.
private struct FoodDietFitRow: View {
    let fit: V1FoodHealth.DietFit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Image(systemName: FoodHealthPresentation.dietSymbol(fit.status))
                .foregroundStyle(FoodHealthPresentation.dietTone(fit.status))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(fit.label)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                Text(fit.reason)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusWord)
    }

    private var statusWord: String {
        switch fit.status {
        case .compatible: "compatible"
        case .uncertain: "incertain"
        case .incompatible: "incompatible"
        }
    }
}

/// The additives by risk, folded: the risky ones already lead « À surveiller ».
private struct FoodAdditivesRow: View {
    let health: V1FoodHealth
    let isCompleting: Bool

    var body: some View {
        if let status = FoodHealthPresentation.additiveStatus(health, isCompleting: isCompleting) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "flask")
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(status)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer(minLength: 0)
                if isCompleting { ProgressView().controlSize(.small) }
            }
        } else if !health.additives.isEmpty {
            DisclosureGroup {
                ForEach(health.additives) { additive in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(additive.code) · \(additive.name)")
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.foreground)
                        Spacer(minLength: SharpitSpacing.xs)
                        Text(additive.risk.label)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(riskTone(additive.risk))
                    }
                    .accessibilityElement(children: .combine)
                }
            } label: {
                Label(
                    health.additives.count == 1 ? "1 additif" : "\(health.additives.count) additifs",
                    systemImage: "flask"
                )
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
            }
            .tint(SharpitColor.mutedForeground)
        }
    }

    private func riskTone(_ risk: V1FoodHealth.AdditiveRisk) -> Color {
        switch risk {
        case .none: SharpitColor.signalRecovery
        case .limited: SharpitColor.signalCaution
        case .high: SharpitColor.signalRisk
        }
    }
}

/// « Comment est calculé le score ? », folded.
private struct FoodHealthMethodRow: View {
    let isPartial: Bool

    var body: some View {
        DisclosureGroup {
            Text(isPartial ? FoodHealthPresentation.partialMethod : FoodHealthPresentation.method)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Label("Comment est calculé le score ?", systemImage: "info.circle")
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
        }
        .tint(SharpitColor.mutedForeground)
    }
}

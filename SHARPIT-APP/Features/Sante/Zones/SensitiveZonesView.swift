import Charts
import SwiftUI

// MARK: - Tints

extension V1SensitiveZone.Strategy {
    /// Signal colours only: what the zone does to the plan is a state.
    var tint: Color {
        switch self {
        case .protect: SharpitColor.signalRisk
        case .progressive: SharpitColor.signalCaution
        case .correct: SharpitColor.primary
        case .relapseWatch: SharpitColor.signalNeutral
        case .none: SharpitColor.slate
        }
    }

    var symbol: String {
        switch self {
        case .protect: "shield.lefthalf.filled"
        case .progressive: "chart.line.uptrend.xyaxis"
        case .correct: "figure.cooldown"
        case .relapseWatch: "eye"
        case .none: "minus.circle"
        }
    }
}

enum ZoneSeverityTint {
    static func color(_ severity: Int?) -> Color {
        guard let severity else { return SharpitColor.slate }
        if severity == 0 { return SharpitColor.foreground }
        if severity >= 7 { return SharpitColor.signalRisk }
        return severity >= 4 ? SharpitColor.signalCaution : SharpitColor.foreground
    }

    static func caption(_ severity: Int) -> String {
        switch severity {
        case 0: String(localized: "Aucune douleur")
        case 1...3: String(localized: "Légère")
        case 4...6: String(localized: "Modérée")
        case 7...9: String(localized: "Forte")
        default: String(localized: "Insupportable")
        }
    }
}

// MARK: - Santé entry

/// Santé's way in: what the open zones do to the plan, and the question owed, if any.
struct SensitiveZonesCard: View {
    let store: SensitiveZonesStore

    var body: some View {
        NavigationLink {
            SensitiveZonesView(store: store)
        } label: {
            SanteLinkRow(
                title: String(localized: "Zones sensibles"),
                detail: store.zones.flatMap { SensitiveZoneReadout.summary($0.zones) }
                    ?? String(localized: "Une douleur, une blessure, une posture à corriger : déclare-la."),
                status: store.zones.flatMap { SensitiveZoneReadout.prompt($0.zones) }.map { _ in String(localized: "Point à faire") }
            )
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre tes zones sensibles")
    }
}

// MARK: - List

/// Every declared zone, on its mock-up (`docs/adr/0035`): the question owed, what the open zones
/// change to the plan, the open ones with their last readings, then the resolved ones.
struct SensitiveZonesView: View {
    let store: SensitiveZonesStore
    @State private var isDeclaring = false
    @State private var checkingIn: V1SensitiveZone?

    var body: some View {
        Group {
            switch store.phase {
            case .unauthorized:
                SharpitStateMessage.sessionExpired()
            case .failed(let message):
                SharpitStateMessage.failed(message) { Task { await store.load() } }
            case .loading, .loaded:
                content
            }
        }
        .cliniqueSheet(wash: (store.zones?.open.isEmpty ?? true) ? .neutral : .watch, height: 240)
        .navigationTitle("Zones sensibles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("") }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Signaler une zone") { isDeclaring = true }
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
            }
        }
        .cliniqueReturnButton(to: .body, symbol: "heart", label: String(localized: "Santé"))
        .sheet(isPresented: $isDeclaring) {
            SensitiveZoneFormSheet(
                draft: SensitiveZoneDraft(),
                bodyParts: store.zones?.bodyParts ?? [],
                figure: store.figure,
                isNew: true
            ) { draft in
                await store.declare(draft)
            }
        }
        .sheet(item: $checkingIn) { zone in
            ZoneCheckinSheet(zone: zone) { draft in
                await store.checkin(zone, draft)
            }
        }
        .task { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        let zones = store.zones ?? V1SensitiveZones()
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zones sensibles")
                        .font(SharpitTypography.system(size: 32, weight: .semibold, relativeTo: .largeTitle))
                        .tracking(-0.6)
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                    Text(SensitiveZoneReadout.count(open: zones.open.count, resolved: zones.resolved.count))
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                }
                if zones.zones.isEmpty {
                    emptyState
                } else {
                    question(zones.open)
                    planEffects(zones.open)
                    group(String(localized: "Ouvertes"), zones.open)
                    group(String(localized: "Résolues"), zones.resolved)
                    if zones.open.contains(where: { SensitiveZoneBody.isOnMap($0.bodyPart) }) {
                        SensitiveZonesBodyOverview(zones: zones.open, figure: store.figure)
                    }
                }
                Text("Indicateur Sharpit pour adapter tes séances, pas un avis médical.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            .padding(.horizontal, 24)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await store.load() }
    }

    /// The one question owed now, in a bordered card: the zone that asks, and the way to answer.
    @ViewBuilder
    private func question(_ open: [V1SensitiveZone]) -> some View {
        if let zone = open.first(where: { $0.resolutionSuggested || $0.followUpQuestion != nil }) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Question du jour")
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(SharpitColor.slate)
                    Text(zone.resolutionSuggested ? String(localized: "« \(zone.title) » ne fait plus mal : c'est résolu ?") : zone.followUpQuestion ?? "")
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if zone.resolutionSuggested {
                        Button("Oui, résolu") { Task { await store.setStatus(zone, to: "RESOLVED") } }
                            .buttonStyle(CliniqueButtonStyle(kind: .outline))
                    }
                    Button(zone.resolutionSuggested ? String(localized: "Pas encore") : String(localized: "Faire le point")) { checkingIn = zone }
                        .buttonStyle(CliniqueButtonStyle(kind: .outline))
                }
            }
            .cliniqueCard()
        }
    }

    /// « Ce que ça change à ton plan »: each open zone's effect, behind a bar in its strategy's tone.
    @ViewBuilder
    private func planEffects(_ open: [V1SensitiveZone]) -> some View {
        let acting = open.filter { $0.affectsTraining && !$0.strategyDetail.isEmpty }
        if !acting.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SanteSectionTitle(String(localized: "Ce que ça change à ton plan"))
                ForEach(acting) { zone in
                    Text(zone.strategyDetail)
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 18)
                        .overlay(alignment: .leading) {
                            Capsule().fill(zone.strategy.status.mark).frame(width: 4).padding(.vertical, 2)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ zones: [V1SensitiveZone]) -> some View {
        if !zones.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SanteSectionTitle(title)
                VStack(spacing: 0) {
                    ForEach(zones) { zone in
                        if zone != zones.first { CliniqueDivider() }
                        NavigationLink {
                            SensitiveZoneDetailView(store: store, zoneId: zone.id)
                        } label: {
                            SensitiveZoneRow(zone: zone)
                        }
                        .buttonStyle(.sharpitPressable)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Aucune zone déclarée")
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
            Text("Déclare une douleur ou une blessure : le plan évite de la charger. Une posture ou un manque de mobilité : le renfo la travaille.")
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
            Button("Signaler une zone") { isDeclaring = true }
                .buttonStyle(CliniqueButtonStyle(kind: .primary))
        }
        .cliniqueCard()
    }
}

extension V1SensitiveZone.Strategy {
    /// The status a strategy reads as on a pill.
    var status: CliniqueStatus {
        switch self {
        case .protect: .protect
        case .progressive: .watch
        case .correct: .good
        case .relapseWatch, .none: .unknown
        }
    }
}

/// One zone in the list: its name and what the plan does with it, then its last readings as
/// bars and where the pain stands — or, resolved, a check and when.
private struct SensitiveZoneRow: View {
    let zone: V1SensitiveZone

    var body: some View {
        if zone.isResolved {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(SharpitColor.pillarRecovery)
                    .accessibilityHidden(true)
                Text(zone.title)
                    .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
                    .foregroundStyle(SharpitColor.slate)
                Spacer(minLength: SharpitSpacing.xs)
                Text(SensitiveZoneReadout.resolved(zone.resolvedAt))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
            .padding(.vertical, 14)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(zone.title)
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: SharpitSpacing.xs)
                    CliniqueStatusPill(zone.strategyLabel, status: zone.strategy.status)
                }
                HStack(alignment: .bottom, spacing: 12) {
                    let levels = SensitiveZoneReadout.levels(zone.readings)
                    if levels.count >= 2 {
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(SharpitColor.pillarNutrition.opacity(index == levels.count - 1 ? 1 : 0.3))
                                    .frame(width: 18, height: 6 + CGFloat(level) * 2)
                            }
                        }
                        .frame(height: 26, alignment: .bottom)
                        .accessibilityHidden(true)
                    }
                    Text(SensitiveZoneReadout.standing(zone))
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                if zone.resolutionSuggested {
                    Text("Plus de douleur depuis deux semaines")
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(SharpitColor.foreground)
                }
            }
            .padding(.vertical, 14)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Detail

/// One zone, followed: where it stands, what the plan does with it, how it evolved, and the
/// actions that move it along — a check-in, an edit, a status change.
struct SensitiveZoneDetailView: View {
    let store: SensitiveZonesStore
    let zoneId: String

    @State private var isEditing = false
    @State private var isCheckingIn = false
    @State private var confirmsResolution = false

    var body: some View {
        Group {
            if let zone = store.zone(zoneId) {
                detail(zone)
            } else {
                SharpitStateMessage(
                    title: String(localized: "Zone introuvable"),
                    symbol: "questionmark.circle",
                    detail: String(localized: "Elle a peut-être été supprimée.")
                )
            }
        }
        .background(SharpitCanvasBackground())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ zone: V1SensitiveZone) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                ZoneHeader(zone: zone)
                if let error = store.saveError {
                    Text(error)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
                prompt(zone)
                ZoneTrainingEffect(zone: zone)
                actions(zone)
                if zone.readings.count >= 2 {
                    ZoneSeverityChart(readings: zone.readings)
                }
                if !zone.timeline.isEmpty {
                    ZoneTimeline(entries: zone.timeline)
                }
                if let description = zone.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        SharpitEyebrow(String(localized: "Notes"))
                        Text(description)
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .refreshable { await store.load() }
        .navigationTitle(zone.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Modifier") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            SensitiveZoneFormSheet(
                draft: SensitiveZoneDraft(zone: zone, offered: store.zones?.bodyParts ?? []),
                bodyParts: store.zones?.bodyParts ?? [],
                figure: store.figure,
                isNew: false
            ) { draft in
                await store.update(zone, with: draft)
            }
        }
        .sheet(isPresented: $isCheckingIn) {
            ZoneCheckinSheet(zone: zone) { draft in
                await store.checkin(zone, draft)
            }
        }
        .confirmationDialog(
            String(localized: "Marquer « \(zone.title) » comme résolue ?"),
            isPresented: $confirmsResolution,
            titleVisibility: .visible
        ) {
            Button("Marquer résolue") { Task { await store.setStatus(zone, to: "RESOLVED") } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le plan cesse de l'éviter. Pendant six semaines, il garde une vigilance contre la rechute.")
        }
    }

    /// The one question owed now: close it, or how is it.
    @ViewBuilder
    private func prompt(_ zone: V1SensitiveZone) -> some View {
        if zone.resolutionSuggested {
            ZonePromptCard(
                text: String(localized: "Aucune douleur depuis au moins deux semaines. C'est derrière toi ?"),
                tint: SharpitColor.signalRecovery
            ) {
                Button("Oui, c'est résolu") { Task { await store.setStatus(zone, to: "RESOLVED") } }
                    .sharpitGlassButton(prominent: true)
                    .tint(SharpitColor.signalRecovery)
                Button("Pas encore") { isCheckingIn = true }
                    .sharpitGlassButton(prominent: false)
            }
        } else if let question = zone.followUpQuestion {
            ZonePromptCard(text: question, tint: SharpitColor.signalCaution) {
                Button("Faire le point") { isCheckingIn = true }
                    .sharpitGlassButton(prominent: true)
                    .tint(SharpitColor.primary)
            }
        }
    }

    private func actions(_ zone: V1SensitiveZone) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            if zone.isResolved {
                Button {
                    Task { await store.setStatus(zone, to: "ACTIVE") }
                } label: {
                    Label("Ça revient", systemImage: "arrow.uturn.backward")
                        .font(SharpitTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .sharpitGlassButton(prominent: true)
                .tint(SharpitColor.primary)
            } else {
                Button {
                    isCheckingIn = true
                } label: {
                    Label("Faire le point", systemImage: "square.and.pencil")
                        .font(SharpitTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .sharpitGlassButton(prominent: true)
                .tint(SharpitColor.primary)
                HStack(spacing: SharpitSpacing.xs) {
                    ForEach(ZoneStatusAction.available(for: zone.status)) { action in
                        Button {
                            if action == .resolve {
                                confirmsResolution = true
                            } else {
                                Task { await store.setStatus(zone, to: action.rawValue) }
                            }
                        } label: {
                            Label(action.label, systemImage: action.symbol)
                                .font(SharpitTypography.meta.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .sharpitGlassButton(prominent: false)
                    }
                }
            }
        }
    }
}

private struct ZoneHeader: View {
    let zone: V1SensitiveZone

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.md) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                HStack(spacing: SharpitSpacing.xs) {
                    SharpitInlineTag(zone.categoryLabel)
                    Text(zone.statusLabel)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
                Text(zone.title)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(zone.place)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                Text(sinceLine)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(SensitiveZoneReadout.severity(zone.severity))
                    .font(SharpitTypography.gaugeScore)
                    .tracking(SharpitTypography.gaugeScoreTracking)
                    .monospacedDigit()
                    .foregroundStyle(ZoneSeverityTint.color(zone.isResolved ? nil : zone.severity))
                Text(zone.functionalImpactLabel ?? "douleur")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sinceLine: String {
        let since = zone.startDate.formatted(.dateTime.day().month(.wide).year().locale(SharpitLocale.current))
        let relapses = SensitiveZoneReadout.relapses(zone.recurrenceCount).map { " · \($0)" } ?? ""
        return String(localized: "Depuis le \(since)\(relapses)")
    }
}

private struct ZonePromptCard<Actions: View>: View {
    let text: String
    let tint: Color
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text(text)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: SharpitSpacing.xs) { actions() }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitContainerCorner(SharpitRadius.panel)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous))
    }
}

/// What the plan does with the zone, in the web's words, and what it changes now.
private struct ZoneTrainingEffect: View {
    let zone: V1SensitiveZone

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(String(localized: "Dans ton plan"))
            Label(zone.strategyLabel, systemImage: zone.strategy.symbol)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(zone.strategy.tint)
            Text(zone.affectsTraining ? zone.strategyDetail : String(localized: "Tenue à l'écart de la génération des séances."))
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
            if let upcoming = SensitiveZoneReadout.upcoming(zone.upcomingSessionsLoading) {
                Text(upcoming)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.signalCaution)
            }
            if !zone.bodyPartRecognized {
                Text("Zone non reconnue : le plan ne peut pas vérifier qu'il l'épargne. Choisis-la dans la liste pour qu'il le fasse.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalCaution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

/// The readings over time, on the 0–10 scale the athlete answers on.
private struct ZoneSeverityChart: View {
    let readings: [V1ZoneTimelineEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(String(localized: "Évolution"))
            Chart(readings) { entry in
                LineMark(x: .value(String(localized: "Date"), entry.date), y: .value(String(localized: "Douleur"), entry.severity ?? 0))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(SharpitColor.primary)
                PointMark(x: .value(String(localized: "Date"), entry.date), y: .value(String(localized: "Douleur"), entry.severity ?? 0))
                    .foregroundStyle(ZoneSeverityTint.color(entry.severity))
                    .symbolSize(28)
            }
            .chartYScale(domain: 0...10)
            .chartYAxis {
                AxisMarks(values: [0, 5, 10]) { _ in
                    AxisGridLine().foregroundStyle(SharpitColor.divider)
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(SharpitLocale.current))
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Évolution de la douleur")
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

/// Every point, newest first: readings, and the status changes between them.
private struct ZoneTimeline: View {
    /// Grows with the text: a fixed 64 pt broke the date inside its words at the largest sizes.
    @ScaledMetric(relativeTo: .footnote) private var dateWidth: CGFloat = 64
    let entries: [V1ZoneTimelineEntry]
    @State private var showsAll = false

    private static let preview = 6

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(String(localized: "Historique"))
            VStack(spacing: 0) {
                ForEach(shown) { entry in
                    row(entry)
                    if entry != shown.last {
                        Rectangle().fill(SharpitColor.divider).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
            if entries.count > Self.preview && !showsAll {
                Button("Tout afficher (\(entries.count))") {
                    SharpitMotion.run { showsAll = true }
                }
                .font(SharpitTypography.meta.weight(.semibold))
            }
        }
    }

    private var shown: [V1ZoneTimelineEntry] {
        showsAll ? entries : Array(entries.prefix(Self.preview))
    }

    private func row(_ entry: V1ZoneTimelineEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Text(entry.date.formatted(.dateTime.day().month(.abbreviated).locale(SharpitLocale.current)))
                .font(SharpitTypography.meta)
                .monospacedDigit()
                .foregroundStyle(SharpitColor.slate)
                .frame(width: dateWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(entry.kind == .status ? SharpitTypography.bodyEmphasis : SharpitTypography.body)
                    .foregroundStyle(entry.kind == .status ? SharpitColor.primary : SharpitColor.foreground)
                if let impact = entry.functionalImpact {
                    Text(SensitiveZoneOptions.label(impact, in: SensitiveZoneOptions.impacts))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
                if let comment = entry.comment, !comment.isEmpty {
                    Text(comment)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, SharpitSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

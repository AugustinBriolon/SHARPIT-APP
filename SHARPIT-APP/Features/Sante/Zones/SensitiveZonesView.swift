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
        case .none: SharpitColor.mutedForeground
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
        guard let severity else { return SharpitColor.mutedForeground }
        if severity == 0 { return SharpitColor.signalRecovery }
        if severity >= 7 { return SharpitColor.signalRisk }
        return severity >= 4 ? SharpitColor.signalCaution : SharpitColor.foreground
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
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitCardHeader(title: "Zones sensibles", symbol: "figure.walk.motion")
                if let zones = store.zones?.zones, let summary = SensitiveZoneReadout.summary(zones) {
                    Text(summary)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    if let prompt = SensitiveZoneReadout.prompt(zones) {
                        Text(prompt)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalCaution)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Une douleur, une blessure, une posture à corriger : déclare-la, le plan s'adapte.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Ouvre tes zones sensibles")
    }
}

// MARK: - List

/// Every declared zone: the open ones by what they do to the plan, then the resolved ones.
struct SensitiveZonesView: View {
    let store: SensitiveZonesStore
    @State private var isDeclaring = false

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
        .background(SharpitCanvasBackground())
        .navigationTitle("Zones sensibles")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isDeclaring = true
                } label: {
                    Label("Déclarer une zone", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isDeclaring) {
            SensitiveZoneFormSheet(
                draft: SensitiveZoneDraft(),
                bodyParts: store.zones?.bodyParts ?? [],
                isNew: true
            ) { draft in
                await store.declare(draft)
            }
        }
        .task { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        let zones = store.zones ?? V1SensitiveZones()
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                if zones.zones.isEmpty {
                    emptyState
                } else {
                    group("En cours", zones.open)
                    group("Résolues", zones.resolved)
                }
                Text("Indicateur Sharpit pour adapter tes séances, pas un avis médical.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private func group(_ title: String, _ zones: [V1SensitiveZone]) -> some View {
        if !zones.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow(title)
                VStack(spacing: 0) {
                    ForEach(zones) { zone in
                        NavigationLink {
                            SensitiveZoneDetailView(store: store, zoneId: zone.id)
                        } label: {
                            SensitiveZoneRow(zone: zone)
                        }
                        .buttonStyle(.plain)
                        if zone != zones.last {
                            Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text("Aucune zone déclarée")
                .font(SharpitTypography.cardTitle)
                .tracking(SharpitTypography.cardTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            Text("Déclare une douleur ou une blessure : le plan évite de la charger. Une posture ou un manque de mobilité : le renfo la travaille.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                isDeclaring = true
            } label: {
                Text("Déclarer une zone")
                    .font(SharpitTypography.bodyEmphasis)
                    .frame(maxWidth: .infinity)
            }
            .sharpitGlassButton(prominent: true)
            .tint(SharpitColor.primary)
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

/// One zone in the list: its name and place, what it does to the plan, today's reading.
private struct SensitiveZoneRow: View {
    let zone: V1SensitiveZone

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(zone.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                Text("\(zone.categoryLabel) · \(zone.place)")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
                if zone.isResolved {
                    Text(resolvedLine)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                } else {
                    Label(zone.strategyLabel, systemImage: zone.strategy.symbol)
                        .font(SharpitTypography.meta.weight(.semibold))
                        .foregroundStyle(zone.strategy.tint)
                        .labelStyle(.titleAndIcon)
                }
                if zone.resolutionSuggested {
                    Text("Plus de douleur depuis deux semaines")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRecovery)
                }
            }
            Spacer(minLength: 0)
            if !zone.isResolved {
                Text(SensitiveZoneReadout.severity(zone.severity))
                    .font(SharpitTypography.data)
                    .tracking(SharpitTypography.dataTracking)
                    .monospacedDigit()
                    .foregroundStyle(ZoneSeverityTint.color(zone.severity))
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, SharpitSpacing.sm)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var resolvedLine: String {
        guard let resolvedAt = zone.resolvedAt else { return "Résolue" }
        return "Résolue le \(resolvedAt.formatted(.dateTime.day().month(.wide).locale(SharpitLocale.french)))"
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
                    title: "Zone introuvable",
                    symbol: "questionmark.circle",
                    detail: "Elle a peut-être été supprimée."
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
                        SharpitEyebrow("Notes")
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
            "Marquer « \(zone.title) » comme résolue ?",
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
                text: "Aucune douleur depuis au moins deux semaines. C'est derrière toi ?",
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
        .disabled(store.isSaving)
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
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Text(zone.title)
                    .font(SharpitTypography.cardTitle)
                    .tracking(SharpitTypography.cardTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(zone.place)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Text(sinceLine)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
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
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sinceLine: String {
        let since = zone.startDate.formatted(.dateTime.day().month(.wide).year().locale(SharpitLocale.french))
        let relapses = SensitiveZoneReadout.relapses(zone.recurrenceCount).map { " · \($0)" } ?? ""
        return "Depuis le \(since)\(relapses)"
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
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous))
    }
}

/// What the plan does with the zone, in the web's words, and what it changes now.
private struct ZoneTrainingEffect: View {
    let zone: V1SensitiveZone

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Dans ton plan")
            Label(zone.strategyLabel, systemImage: zone.strategy.symbol)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(zone.strategy.tint)
            Text(zone.affectsTraining ? zone.strategyDetail : "Tenue à l'écart de la génération des séances.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
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
            SharpitEyebrow("Évolution")
            Chart(readings) { entry in
                LineMark(x: .value("Date", entry.date), y: .value("Douleur", entry.severity ?? 0))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(SharpitColor.primary)
                PointMark(x: .value("Date", entry.date), y: .value("Douleur", entry.severity ?? 0))
                    .foregroundStyle(ZoneSeverityTint.color(entry.severity))
                    .symbolSize(28)
            }
            .chartYScale(domain: 0...10)
            .chartYAxis {
                AxisMarks(values: [0, 5, 10]) { _ in
                    AxisGridLine().foregroundStyle(SharpitColor.analysisGrid)
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(SharpitLocale.french))
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
    let entries: [V1ZoneTimelineEntry]
    @State private var showsAll = false

    private static let preview = 6

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Historique")
            VStack(spacing: 0) {
                ForEach(shown) { entry in
                    row(entry)
                    if entry != shown.last {
                        Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1)
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
            Text(entry.date.formatted(.dateTime.day().month(.abbreviated).locale(SharpitLocale.french)))
                .font(SharpitTypography.meta)
                .monospacedDigit()
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(entry.kind == .status ? SharpitTypography.bodyEmphasis : SharpitTypography.body)
                    .foregroundStyle(entry.kind == .status ? SharpitColor.primary : SharpitColor.foreground)
                if let impact = entry.functionalImpact {
                    Text(SensitiveZoneOptions.label(impact, in: SensitiveZoneOptions.impacts))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                if let comment = entry.comment, !comment.isEmpty {
                    Text(comment)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, SharpitSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

import MapKit
import SwiftUI
import Charts

struct ActivityDetailView: View {
    let activity: String
    let initialActivity: V1ActivityListItem?
    let client: any ActivityServing
    let tokenProvider: () async throws -> String

    @State private var phase: DetailPhase
    @State private var appeared = false
    @State private var isGeneratingNarrative = false
    @State private var streamPayload: V1ActivityStreamPayload?
    @State private var isEnriching = false
    @State private var showingCompliance = false
    @State private var showingSubjective = false
    @Environment(\.dismiss) private var dismiss

    init(
        activity: String,
        initialActivity: V1ActivityListItem? = nil,
        client: any ActivityServing,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.activity = activity
        self.initialActivity = initialActivity
        self.client = client
        self.tokenProvider = tokenProvider
        _phase = State(initialValue: initialActivity.map { .loaded(.preview(from: $0)) } ?? .loading)
        _appeared = State(initialValue: initialActivity != nil)
    }

    var body: some View {
        GeometryReader { proxy in
            switch phase {
            case .loading:
                ActivityDetailLoading(viewportHeight: proxy.size.height)
                    .ignoresSafeArea()
            case .loaded(let detail):
                let route = detail.stream?.route.isEmpty == false
                    ? detail.stream?.route ?? []
                    : streamPayload?.route ?? []
                let reservesMapSpace = !route.isEmpty ||
                    (isEnriching && detail.type.supportsPotentialRoute)
                if reservesMapSpace {
                    ZStack(alignment: .top) {
                        Group {
                            if let stream = detail.stream, stream.available, !stream.route.isEmpty {
                                ActivityRouteHero(route: stream.route, tone: activityTone(detail.type))
                            } else if !route.isEmpty {
                                ActivityRouteHero(route: route, tone: activityTone(detail.type))
                            } else {
                                ActivityRouteLoadingSurface()
                            }
                        }
                        .frame(height: proxy.size.height)

                        ScrollView {
                            VStack(spacing: 0) {
                                Color.clear
                                    .frame(height: proxy.size.height * 0.62)

                                ActivityDetailContent(
                                    detail: detail,
                                    streamPayload: streamPayload,
                                    appeared: appeared,
                                    isGeneratingNarrative: isGeneratingNarrative,
                                    onGenerateNarrative: { Task { await generateNarrative() } },
                                    splits: activitySplits(for: detail),
                                    onShowCompliance: { showingCompliance = true },
                                    onShowSubjective: { showingSubjective = true }
                                )
                                .frame(width: proxy.size.width, alignment: .leading)
                            }
                            .frame(width: proxy.size.width, alignment: .leading)
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .ignoresSafeArea()
                } else {
                    ScrollView {
                        ActivityDetailContent(
                            detail: detail,
                            streamPayload: streamPayload,
                            appeared: appeared,
                            isGeneratingNarrative: isGeneratingNarrative,
                            onGenerateNarrative: { Task { await generateNarrative() } },
                            splits: activitySplits(for: detail),
                            onShowCompliance: { showingCompliance = true },
                            onShowSubjective: { showingSubjective = true }
                        )
                        .frame(width: proxy.size.width, alignment: .leading)
                    }

                }
            case .failed(let message):
                ScrollView {
                    ContentUnavailableView {
                        Label("Détail indisponible", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Réessayer") { Task { await load() } }
                    }
                }
            case .unauthorized:
                ScrollView {
                    ContentUnavailableView("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
                }
            }
        }
        .background(SharpitCanvasBackground())
        .modifier(ScrollUnderGlass())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .topLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .sheet(isPresented: $showingCompliance) {
                if case .loaded(let detail) = phase, let analysis = detail.plannedSession?.analysis {
                    ComplianceDetailSheet(
                        title: detail.plannedSession?.title ?? "Séance planifiée",
                        analysis: analysis
                    )
                    .presentationDetents([.medium, .large])
                    .sharpitSheet()
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(isPresented: $showingSubjective) {
                if case .loaded(let detail) = phase {
                    SubjectiveEditorSheet(
                        rpe: detail.rpe,
                        feeling: detail.feeling,
                        isSaving: false,
                        onSave: { rpe, feeling in
                            Task { await saveSubjective(rpe: rpe, feeling: feeling) }
                        }
                    )
                    .presentationDetents([.medium])
                    .sharpitSheet()
                    .presentationDragIndicator(.visible)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 12)
            .accessibilityLabel("Retour")
        }

        .task {
            await load()
        }
    }

    @MainActor
    private func saveSubjective(rpe: Double?, feeling: String?) async {
            do {
                let token = try await tokenProvider()
                try await client.updateSubjective(id: activity, rpe: rpe, feeling: feeling, token: token)
                showingSubjective = false
                await load()
            } catch is CancellationError {
            } catch {
            }
        }

    private func activitySplits(for detail: V1ActivityDetail) -> [ActivitySplit] {
        guard detail.type.supportsSplits else { return [] }
        return ActivitySplit.make(
            samples: streamPayload?.samples ?? [],
            totalDuration: detail.duration,
            segmentDistance: detail.type == .bike ? 5_000 : 1_000
        )
    }

    @MainActor
    private func generateNarrative() async {
        guard !isGeneratingNarrative else { return }
        isGeneratingNarrative = true
        defer { isGeneratingNarrative = false }
        do {
            let token = try await tokenProvider()
            let detail = try await client.generateNarrative(id: activity, token: token)
            withAnimation(SharpitMotion.reveal) {
                phase = .loaded(detail)
            }
        } catch is CancellationError {
        } catch {
        }
    }

    @MainActor
    private func load() async {
        do {
            isEnriching = initialActivity != nil
            let token = try await tokenProvider()
            async let detailRequest = client.activity(id: activity, token: token)
            async let streamRequest = client.activityStream(id: activity, token: token)
            let detail = try await detailRequest
            streamPayload = try? await streamRequest
            isEnriching = false
            withAnimation(SharpitMotion.reveal) {
                phase = .loaded(detail)
            }

            guard !SharpitMotion.reduceMotion else {
                appeared = true
                return
            }
            SharpitMotion.run {
                appeared = true
            }
        } catch is CancellationError {
        } catch let error as SharpitAPIError where error == .unauthorized {
            phase = .unauthorized
        } catch {
            phase = .failed("Impossible de récupérer cette activité pour le moment.")
        }
    }
}

private enum DetailPhase {
    case loading
    case loaded(V1ActivityDetail)
    case failed(String)
    case unauthorized
}

private struct ActivityDetailContent: View {
    @Environment(ShellRouter.self) private var router

    let detail: V1ActivityDetail
    let streamPayload: V1ActivityStreamPayload?
    let appeared: Bool
    let isGeneratingNarrative: Bool
    let onGenerateNarrative: () -> Void
    let splits: [ActivitySplit]
    let onShowCompliance: () -> Void
    let onShowSubjective: () -> Void
    @State private var selectedChartMetrics: [ActivityChartMetric] = [.heartRate]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                HStack {
                    Label(detail.type.label, systemImage: detail.type.symbolName)
                        .font(SharpitTypography.eyebrow)
                        .tracking(SharpitTypography.eyebrowTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(tone)
                    Spacer()
                    Text(dateLabel)
                        .font(.subheadline)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                Text(detail.title ?? detail.type.label)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .tracking(-0.8)
                    .lineLimit(3)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .padding(.top, 56)

            contextSection
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(SharpitMotion.reveal.delay(0.04), value: appeared)

            metricGrid
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(SharpitMotion.reveal.delay(0.06), value: appeared)

            if detail.type == .triathlon, !detail.multisportLegs.isEmpty {
                multisportLegsSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(0.1), value: appeared)
            }

            coachAnalysis
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(SharpitMotion.reveal.delay(0.18), value: appeared)

            // The session the athlete is reading is exactly what they would ask about.
            CoachDiscussButton(title: "Discuter de cette séance") {
                router.discussWithCoach(
                    about: CoachDiscuss.describe(
                        .activity(activityId: detail.id),
                        name: detail.title ?? detail.type.label
                    )
                )
            }
            .opacity(appeared ? 1 : 0)
            .animation(SharpitMotion.reveal.delay(0.22), value: appeared)

            if hasSessionSummaryData {
                sessionSummary
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(0.24), value: appeared)
            }

            if !splits.isEmpty {
                ActivitySplitsSection(
                    splits: splits,
                    tone: tone,
                    segmentDistance: detail.type == .bike ? 5_000 : 1_000
                )
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(SharpitMotion.reveal.delay(0.3), value: appeared)
            }

            if !availableChartMetrics.isEmpty {
                ActivityChartsSection(
                    samples: streamPayload?.samples ?? [],
                    metrics: availableChartMetrics,
                    selection: $selectedChartMetrics,
                    tone: tone
                )
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(SharpitMotion.reveal.delay(0.36), value: appeared)
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.lg)
        .padding(.bottom, SharpitSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(SharpitElevatedColor.sheet)
                .sharpitShadow(.panel)
        )
        .environment(\.sharpitElevation, .sheet)
        .foregroundStyle(SharpitColor.foreground)
    }

    private var metricGrid: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Résumé de séance")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SharpitColor.mutedForeground)
            LazyVGrid(columns: [GridItem(.flexible(minimum: 0)), GridItem(.flexible(minimum: 0))], spacing: 22) {
                ForEach(primaryMetrics) { metric in
                    ActivityHeroMetric(metric: metric)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SharpitColor.analysisSurfaceAlt, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var primaryMetrics: [ActivityHeroMetricData] {
        var metrics: [ActivityHeroMetricData] = []
        if let duration = detail.duration { metrics.append(.init(label: "Durée", value: ActivityFormat.duration(duration), unit: nil)) }
        if detail.type == .strength {
            if !detail.strengthSets.isEmpty { metrics.append(.init(label: "Séries", value: "\(totalStrengthSets)", unit: nil)) }
            if let volume = strengthVolume { metrics.append(.init(label: "Volume", value: "\(Int(volume.rounded()))", unit: "kg")) }
        } else if let distance = effectiveDistanceM {
            metrics.append(.init(label: "Distance", value: distance >= 1_000 ? String(format: "%.1f", distance / 1_000) : "\(Int(distance.rounded()))", unit: distance >= 1_000 ? "km" : "m"))
        }
        if let elevation = detail.elevationM, detail.type != .swim && detail.type != .strength { metrics.append(.init(label: "Dénivelé", value: "\(Int(elevation.rounded()))", unit: "m")) }
        if detail.type == .swim, let pace = detail.avgPaceSecPer100m { metrics.append(.init(label: "Allure", value: ActivityFormat.pace(pace), unit: "/100 m")) }
        else if detail.type != .strength, let pace = detail.paceSecPerKm { metrics.append(.init(label: "Allure", value: ActivityFormat.pace(pace), unit: "/km")) }
        return metrics
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SubjectiveTagButton(
                    title: subjectiveValue,
                    symbol: "face.smiling",
                    tone: tone,
                    action: onShowSubjective
                )

                if let analysis = detail.plannedSession?.analysis {
                    SubjectiveTagButton(
                        title: "Conformité \(analysis.complianceScore.map { "\(Int($0.rounded()))%" } ?? "À voir")",
                        symbol: "checkmark.seal",
                        tone: tone,
                        action: onShowCompliance
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let weather = detail.weather, let weatherLabel = V1ActivityWeather(rawValue: weather).label {
                ContextChip(title: weatherLabel, symbol: "cloud.sun")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subjectiveValue: String {
        switch (detail.rpe, detail.feeling) {
        case let (rpe?, feeling?) where !feeling.isEmpty:
            "RPE \(Int(rpe.rounded())) · \(feeling)"
        case let (rpe?, _):
            "RPE \(Int(rpe.rounded())) · à compléter"
        case let (_, feeling?) where !feeling.isEmpty:
            "RPE à compléter · \(feeling)"
        default:
            "Ajouter maintenant"
        }
    }

    private func plannedComparison(analysis: V1PlannedSessionAnalysis) -> some View {
        Button(action: onShowCompliance) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(tone)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Conformité au plan")
                        .font(.subheadline.weight(.semibold))
                    Text(detail.plannedSession?.title ?? "Séance planifiée")
                        .font(.caption)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer()
                if let score = analysis.complianceScore {
                    Text("\(Int(score.rounded()))%")
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(tone)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .padding(SharpitSpacing.cardPadding)
            .background(SharpitColor.analysisSurfaceAlt, in: RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var coachAnalysis: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Analyse du coach", systemImage: "sparkles")
            if let narrative = detail.narrativeAnalysis {
                Text(narrative.headline)
                    .font(SharpitTypography.sectionTitle)
                    .tracking(SharpitTypography.sectionTitleTracking)
                Text(narrative.narrative).font(.body).lineSpacing(4)
            } else if detail.plannedSession?.analysis != nil {
                Label("Conformité déjà analysée", systemImage: "checkmark.seal")
                    .font(.headline)
                Text("Le comparatif détaillé avec ta séance planifiée est affiché juste au-dessus.")
                    .font(.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
            } else {
                Label("Ton retour est prêt à être généré", systemImage: "sparkles").font(.headline)
                Text("SHARPIT peut croiser ta séance, ton ressenti et les données disponibles pour te donner une lecture claire et actionnable.")
                    .font(.body).foregroundStyle(SharpitColor.mutedForeground)
                Button(action: onGenerateNarrative) {
                    HStack {
                        if isGeneratingNarrative { ProgressView().tint(.white) }
                        Text(isGeneratingNarrative ? "Analyse en cours…" : "Générer l’analyse")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, SharpitSpacing.cardPadding)
                    .padding(.vertical, 12)
                    .background(tone, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isGeneratingNarrative)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [tone.opacity(0.13), SharpitColor.analysisSurfaceAlt],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous)
        )
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Lecture de séance")
            if detail.type == .strength {
                HStack(spacing: SharpitSpacing.xs) {
                    SummarySignal(label: "Exercices", value: "\(exerciseCount)", symbol: "figure.strengthtraining.traditional")
                    SummarySignal(label: "Séries", value: "\(totalStrengthSets)", symbol: "repeat")
                    if let volume = strengthVolume {
                        SummarySignal(label: "Volume", value: "\(Int(volume.rounded())) kg", symbol: "scalemass")
                    }
                }
            } else if detail.type == .swim {
                HStack(spacing: SharpitSpacing.xs) {
                    if let sets = detail.swimSets {
                        SummarySignal(label: "Séries", value: "\(Int(sets.rounded()))", symbol: "water.waves")
                    }
                    if let swolf = detail.swolf {
                        SummarySignal(label: "Swolf", value: "\(Int(swolf.rounded()))", symbol: "waveform.path.ecg")
                    }
                }
            } else if detail.type != .triathlon {
                HStack(spacing: SharpitSpacing.xs) {
                    if let elevation = detail.elevationM {
                        SummarySignal(label: "Dénivelé", value: "\(Int(elevation.rounded())) m", symbol: "mountain.2")
                    }
                    if let power = detail.avgPower {
                        SummarySignal(label: "Puissance", value: "\(Int(power.rounded())) W", symbol: "bolt")
                    }
                    if let calories = detail.calories {
                        SummarySignal(label: "Calories", value: "\(Int(calories.rounded()))", symbol: "flame")
                    }
                }
            }
            if let notes = detail.notes, !notes.isEmpty {
                Text(notes).font(.subheadline).foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(hasSessionSummaryData ? 1 : 0)
    }

    private var hasSessionSummaryData: Bool {
        detail.notes?.isEmpty == false ||
        detail.type == .strength && !detail.strengthSets.isEmpty ||
        detail.type == .swim && (detail.swimSets != nil || detail.swolf != nil) ||
        detail.type != .strength && detail.type != .swim && (detail.elevationM != nil || detail.avgPower != nil || detail.calories != nil)
    }

    private var exerciseCount: Int {
        Set(detail.strengthSets.map(\.exercise)).count
    }

    private var totalStrengthSets: Int {
        detail.strengthSets.reduce(0) { $0 + $1.sets }
    }

    private var strengthVolume: Double? {
        let volume = detail.strengthSets.reduce(0.0) { $0 + Double($1.sets * $1.reps) * ($1.weightKg ?? 0) }
        return volume > 0 ? volume : nil
    }

    private var tone: Color {
        activityTone(detail.type)
    }

    private var availableChartMetrics: [ActivityChartMetric] {
        let samples = streamPayload?.samples ?? []
        return ActivityChartMetric.allCases.filter { metric in
            samples.contains { metric.value(for: $0) != nil }
        }
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM yyyy")
        return formatter.string(from: detail.date)
    }

    private var distanceValue: String {
        guard let distanceM = effectiveDistanceM else { return "—" }
        return distanceM >= 1_000
            ? String(format: "%.1f", distanceM / 1_000) + " km"
            : "\(Int(distanceM.rounded())) m"
    }

    private var effectiveDistanceM: Double? {
        detail.distanceM ?? streamPayload?.stats?.totalDistance
    }

    private var multisportLegsSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow("Jambes multisport")
            ForEach(detail.multisportLegs) { leg in
                HStack(spacing: SharpitSpacing.sm) {
                    Image(systemName: leg.symbolName)
                        .foregroundStyle(activityTone(leg.activityType))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leg.label)
                            .font(.subheadline.weight(.semibold))
                        Text(ActivityFormat.duration(leg.durationSec))
                            .font(.caption)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    Spacer()
                    if let distance = leg.distanceM {
                        Text(distance >= 1_000
                             ? String(format: "%.1f km", distance / 1_000)
                             : "\(Int(distance.rounded())) m")
                            .font(.subheadline.monospacedDigit())
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var elevationValue: String {
        guard let elevationM = detail.elevationM else { return "—" }
        return "\(Int(elevationM.rounded())) m"
    }

    private var paceValue: String {
        let seconds = detail.paceSecPerKm ?? detail.avgPaceSecPer100m
        guard let seconds else { return "—" }
        if detail.type == .swim {
            return "\(Int(seconds / 60))'\(String(format: "%02d", Int(seconds.rounded()) % 60))\""
        }
        return "\(Int(seconds / 60))'\(String(format: "%02d", Int(seconds.rounded()) % 60))\""
    }

    private var heartRateValue: String {
        detail.avgHr.map { "\(Int($0.rounded()))" } ?? "—"
    }

    private var cadenceNumber: Double? {
        detail.cadence ?? detail.avgCadence
    }

    private var cadenceValue: String {
        cadenceNumber.map { "\(Int($0.rounded()))" } ?? "—"
    }

    private var cadenceLabel: String {
        "Cadence"
    }

    private var caloriesValue: String {
        detail.calories.map { "\(Int($0.rounded()))" } ?? "—"
    }
}

private extension V1ActivityType {
    var supportsPotentialRoute: Bool {
        switch self {
        case .run, .bike, .hike, .triathlon:
            true
        case .swim, .strength, .other:
            false
        }
    }

    var supportsSplits: Bool {
        switch self {
        case .run, .bike, .hike, .triathlon:
            true
        case .swim, .strength, .other:
            false
        }
    }
}

private func activityTone(_ type: V1ActivityType) -> Color {
    SharpitSportTone.accent(for: type)
}

private struct ActivitySplit: Identifiable, Equatable {
    let id: Int
    let distanceLabel: String
    let paceSeconds: Double
    let variation: Double
    let heartRate: Double?
    let elevationGain: Double
    let progress: Double

    static func make(
        samples: [V1ActivityStreamSample],
        totalDuration: Double?,
        segmentDistance: Double
    ) -> [ActivitySplit] {
        guard samples.count > 1 else { return [] }
        let ordered = samples.sorted { $0.d < $1.d }
        guard let totalDistance = ordered.last?.d, totalDistance >= 500 else { return [] }
        let overallPace = totalDuration.map { $0 / totalDistance * 1_000 }
            ?? duration(for: ordered.last!, after: ordered.first!) / totalDistance * 1_000
        guard overallPace > 0 else { return [] }

        let segmentCount = Int(ceil(totalDistance / segmentDistance))
        return (0..<segmentCount).compactMap { index in
            let startDistance = Double(index) * segmentDistance
            let endDistance = min(Double(index + 1) * segmentDistance, totalDistance)
            guard
                let start = sample(at: startDistance, in: ordered),
                let end = sample(at: endDistance, in: ordered),
                end.d > start.d,
                end.t > start.t
            else { return nil }

            let distance = end.d - start.d
            let pace = (end.t - start.t) / distance * 1_000
            let points = ordered.filter { $0.d >= start.d && $0.d <= end.d }
            let heartRates = points.compactMap(\.hr)
            let elevationGain = zip(points, points.dropFirst())
                .reduce(0) { result, pair in result + max(0, (pair.1.alt ?? pair.0.alt ?? 0) - (pair.0.alt ?? pair.1.alt ?? 0)) }

            return ActivitySplit(
                id: index,
                distanceLabel: endDistance - startDistance < segmentDistance
                    ? String(format: "%.1f km", distance / 1_000)
                    : "\(Int(endDistance / 1_000)) km",
                paceSeconds: pace,
                variation: (pace / overallPace - 1) * 100,
                heartRate: heartRates.isEmpty ? nil : heartRates.reduce(0, +) / Double(heartRates.count),
                elevationGain: elevationGain,
                progress: max(0.16, min(1, overallPace / pace))
            )
        }
    }

    private static func sample(at distance: Double, in samples: [V1ActivityStreamSample]) -> V1ActivityStreamSample? {
        samples.min { abs($0.d - distance) < abs($1.d - distance) }
    }

    private static func duration(for end: V1ActivityStreamSample, after start: V1ActivityStreamSample) -> Double {
        max(0, end.t - start.t)
    }
}

private struct ActivitySplitsSection: View {
    let splits: [ActivitySplit]
    let tone: Color
    let segmentDistance: Double

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(segmentDistance == 5_000 ? "Splits tous les 5 km" : "Splits au kilomètre")
            Text("Rythme relatif · les barres les plus longues indiquent une allure plus vive")
                .font(.subheadline)
                .foregroundStyle(SharpitColor.mutedForeground)
            ForEach(splits) { split in
                HStack(alignment: .center, spacing: SharpitSpacing.xs) {
                    Text(split.distanceLabel).font(.subheadline.monospacedDigit()).foregroundStyle(SharpitColor.mutedForeground).frame(width: 52, alignment: .leading)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(ActivityFormat.pace(split.paceSeconds)).font(.headline.monospacedDigit().weight(.semibold))
                            Text(String(format: "%+.0f%%", split.variation)).font(.caption.weight(.semibold)).foregroundStyle(split.variation <= 0 ? .green : .orange)
                        }
                        GeometryReader { proxy in
                            Capsule().fill(SharpitColor.radialTrack).overlay(alignment: .leading) { Capsule().fill(split.variation <= -5 ? SharpitColor.signalRecovery : tone.opacity(0.72)).frame(width: proxy.size.width * split.progress) }
                        }.frame(height: 7)
                    }
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(split.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "—")
                        Text("+\(Int(split.elevationGain.rounded())) m")
                    }.font(.caption.monospacedDigit()).foregroundStyle(SharpitColor.mutedForeground).frame(width: 58, alignment: .trailing)
                }.padding(.vertical, 5)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .background(SharpitColor.analysisSurfaceAlt, in: RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
    }
}

private enum ActivityChartMetric: String, CaseIterable, Identifiable {
    case heartRate
    case pace
    case power
    case elevation
    case cadence

    var id: String { rawValue }

    var label: String {
        switch self {
        case .heartRate: "FC"
        case .pace: "Allure"
        case .power: "Puissance"
        case .elevation: "Dénivelé"
        case .cadence: "Cadence"
        }
    }

    var unit: String {
        switch self {
        case .heartRate: "BPM"
        case .pace: "min/km"
        case .power: "W"
        case .elevation: "m"
        case .cadence: "SPM"
        }
    }

    var color: Color {
        switch self {
        case .heartRate: .red
        case .pace: .orange
        case .power: .purple
        case .elevation: .green
        case .cadence: .blue
        }
    }

    func value(for sample: V1ActivityStreamSample) -> Double? {
        switch self {
        case .heartRate:
            return sample.hr
        case .pace:
            guard let speed = sample.speed, speed > 0.2 else { return nil }
            return 1_000 / speed
        case .power:
            return sample.watts
        case .elevation:
            return sample.alt
        case .cadence:
            return sample.cadence
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .pace:
            return ActivityFormat.pace(value)
        case .heartRate, .power, .elevation, .cadence:
            return "\(Int(value.rounded()))"
        }
    }
}

private struct ActivityChartPoint: Identifiable {
    let id: Int
    let time: Double
    let value: Double
    let metric: ActivityChartMetric
}

private struct ActivityChartsSection: View {
    let samples: [V1ActivityStreamSample]
    let metrics: [ActivityChartMetric]
    @Binding var selection: [ActivityChartMetric]
    let tone: Color

    private func points(for metric: ActivityChartMetric) -> [ActivityChartPoint] {
        samples.enumerated().compactMap { index, sample in
            guard let value = metric.value(for: sample), value.isFinite else { return nil }
            return ActivityChartPoint(id: index, time: sample.t / 60, value: value, metric: metric)
        }
    }

    private func domain(for metric: ActivityChartMetric) -> ClosedRange<Double> {
        let values = points(for: metric).map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else { return 0...1 }
        let margin = maxValue == minValue ? Swift.max(maxValue * 0.08, 0.08) : (maxValue - minValue) * 0.12
        return Swift.max(0, minValue - margin)...(maxValue + margin)
    }

    private var timeDomain: ClosedRange<Double> {
        let times = samples.map { $0.t / 60 }
        guard let first = times.min(), let last = times.max(), first < last else { return 0...1 }
        return first...last
    }

    private func axisValues(for metric: ActivityChartMetric) -> [String] {
        let range = domain(for: metric)
        return [range.upperBound, (range.lowerBound + range.upperBound) / 2, range.lowerBound]
            .map { metric.formatted($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                SharpitEyebrow("Courbes")
                Spacer()
                HStack(spacing: 8) {
                    ForEach(selection) { metric in
                        Label(metric.unit, systemImage: "line.diagonal")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(metric.color)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(metrics) { metric in
                        Button {
                            if selection.contains(metric) {
                                if selection.count > 1 {
                                    selection.removeAll { $0 == metric }
                                }
                            } else if selection.count < 2 {
                                selection.append(metric)
                            }
                        } label: {
                            ActivityMetricToggleLabel(metric: metric, isSelected: selection.contains(metric))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onChange(of: metrics) { _, available in
                selection = selection.filter { available.contains($0) }
                if selection.isEmpty, let first = available.first {
                    selection = [first]
                }
            }

            if selection.contains(where: { points(for: $0).count > 1 }) {
                HStack(alignment: .top, spacing: 6) {
                    if let first = selection.first {
                        ActivityChartAxisLabels(values: axisValues(for: first), color: first.color, alignment: .trailing)
                    }
                    ZStack {
                        if let first = selection.first {
                        Chart(points(for: first)) { point in
                            LineMark(
                                x: .value("Temps", point.time),
                                y: .value(first.unit, point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(first.color)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                        .chartXScale(domain: timeDomain)
                        .chartYScale(domain: domain(for: first))
                        .chartYAxis(.hidden)
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                                AxisValueLabel {
                                    if let minutes = value.as(Double.self) {
                                        Text("\(Int(minutes))′")
                                    }
                                }
                            }
                        }
                    }
                    if selection.count > 1 {
                        let second = selection[1]
                        Chart(points(for: second)) { point in
                            LineMark(
                                x: .value("Temps", point.time),
                                y: .value(second.unit, point.value)
                            )
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(second.color)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                        .chartXScale(domain: timeDomain)
                        .chartYScale(domain: domain(for: second))
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                    }
                    }
                    .frame(maxWidth: .infinity)
                    if selection.count > 1 {
                        let second = selection[1]
                        ActivityChartAxisLabels(values: axisValues(for: second), color: second.color, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .clipped()
            } else {
                Text("Pas assez de données pour afficher cette courbe.")
                    .font(.subheadline)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SharpitColor.analysisSurfaceAlt, in: RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
        .clipped()
    }
}

private struct ActivityChartAxisLabels: View {
    let values: [String]
    let color: Color
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            ForEach(values.indices, id: \.self) { index in
                Text(values[index])
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(color)
                    .frame(maxHeight: .infinity, alignment: index == 0 ? .top : index == values.count - 1 ? .bottom : .center)
            }
        }
        .frame(width: 34, height: 155)
        .padding(.top, 3)
    }
}

private struct ActivityMetricToggleLabel: View {
    let metric: ActivityChartMetric
    let isSelected: Bool

    var body: some View {
        Text(metric.label)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isSelected ? metric.color : Color(uiColor: .tertiarySystemFill), in: Capsule())
    }
}

private struct ComplianceDetailSheet: View {
    let title: String
    let analysis: V1PlannedSessionAnalysis

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                    VStack(alignment: .leading, spacing: 6) {
                        SharpitEyebrow("Conformité au plan")
                        Text(title)
                            .font(.title2.weight(.semibold))
                    }

                    if let score = analysis.complianceScore {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(Int(score.rounded()))%")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                            Text("conforme")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }

                    if let verdict = analysis.verdict, !verdict.isEmpty {
                        DetailCallout(title: "Verdict", text: verdict)
                    }
                    if let summary = analysis.summary, !summary.isEmpty {
                        DetailCallout(title: "Résumé", text: summary)
                    }
                    if let remarks = analysis.remarks, !remarks.isEmpty {
                        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                            SharpitEyebrow("Observations")
                            ForEach(remarks, id: \.self) { remark in
                                Label(remark, systemImage: "arrow.right")
                                    .font(.body)
                            }
                        }
                    }
                    if let recommendation = analysis.recommendation, !recommendation.isEmpty {
                        DetailCallout(title: "Recommandation", text: recommendation)
                    }
                }
                .padding(SharpitSpacing.pageInset)
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct DetailCallout: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SharpitEyebrow(title)
            Text(text)
                .font(.body)
                .lineSpacing(3)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SharpitColor.analysisSurfaceAlt, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct DetailMetric: View {
    let label: String
    let value: String
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(value)
                .font(SharpitTypography.data)
                .lineLimit(1)
            if let unit { Text(unit).font(.caption).foregroundStyle(SharpitColor.mutedForeground) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .background(SharpitElevatedColor.panelOnSheet, in: RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
    }
}

private struct ActivityHeroMetricData: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    let unit: String?
}

private struct ActivityHeroMetric: View {
    let metric: ActivityHeroMetricData

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(metric.label.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.1)
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(1)
            Text(metric.value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let unit = metric.unit { Text(unit).font(.caption).foregroundStyle(SharpitColor.mutedForeground) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SubjectiveTagButton: View {
    let title: String
    let symbol: String
    let tone: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(SharpitElevatedColor.panelOnSheet, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct SubjectiveEditorSheet: View {
    let rpe: Double?
    let feeling: String?
    let isSaving: Bool
    let onSave: (Double?, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRPE: Int?
    @State private var selectedFeeling: Int?

    init(rpe: Double?, feeling: String?, isSaving: Bool, onSave: @escaping (Double?, String?) -> Void) {
        self.rpe = rpe
        self.feeling = feeling
        self.isSaving = isSaving
        self.onSave = onSave
        _selectedRPE = State(initialValue: rpe.map { Int($0.rounded()) })
        _selectedFeeling = State(initialValue: Self.feelingIndex(feeling))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.xl) {
                    VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                        Text("Comment s’est passée la séance ?")
                            .font(SharpitTypography.pageTitle)
                            .tracking(SharpitTypography.pageTitleTracking)
                        Text("Ces deux repères permettent à SHARPIT d’affiner ton suivi.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                    VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                        SharpitEyebrow("Effort perçu")
                        HStack(alignment: .lastTextBaseline, spacing: SharpitSpacing.xs) {
                            Text(selectedRPE.map(String.init) ?? "—")
                                .font(SharpitTypography.pageTitle)
                                .tracking(SharpitTypography.pageTitleTracking)
                            Text("/ 10")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                        RatingGrid(values: Array(1...10), selection: $selectedRPE) { value in
                            Text("\(value)")
                        }
                    }
                    VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                        SharpitEyebrow("Ressenti")
                        // One full-width row per option. In a five-column grid
                        // "Très mauvais" wrapped to two cramped lines, and the label
                        // had to be repeated underneath to be readable at all.
                        RatingRows(values: Array(1...5), selection: $selectedFeeling) { value in
                            feelingLabel(value)
                        }
                    }
                }
                .padding(SharpitSpacing.lg)
            }
            .navigationTitle("Évaluer la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(
                            selectedRPE.map(Double.init) ?? rpe,
                            selectedFeeling.map(feelingLabel) ?? feeling
                        )
                    }
                    .disabled(isSaving || (selectedRPE == nil && selectedFeeling == nil))
                }
            }
        }
    }

    private static func feelingIndex(_ value: String?) -> Int? {
        guard let value else { return nil }
        let normalized = value.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        if normalized.contains("tres mauvais") || normalized == "mauvais" { return 1 }
        if normalized.contains("moyen") { return 3 }
        if normalized.contains("tres bien") || normalized.contains("excellent") { return 5 }
        if normalized == "bien" { return 4 }
        return nil
    }

    private func feelingLabel(_ value: Int) -> String {
        switch value {
        case 1: "Très mauvais"
        case 2: "Mauvais"
        case 3: "Moyen"
        case 4: "Bien"
        default: "Très bien"
        }
    }
}

/// A vertical single-choice list — for options whose labels are words, not digits.
private struct RatingRows<Value: Hashable>: View {
    let values: [Value]
    @Binding var selection: Value?
    let label: (Value) -> String

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ForEach(values, id: \.self) { value in
                let isSelected = selection == value
                Button { selection = value } label: {
                    HStack(spacing: SharpitSpacing.sm) {
                        Text(label(value))
                            .font(SharpitTypography.bodyEmphasis)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(SharpitTypography.label)
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(
                        isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground
                    )
                    .padding(.horizontal, SharpitSpacing.md)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(
                        isSelected ? SharpitColor.primary : SharpitColor.analysisSurfaceAlt,
                        in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

private struct RatingGrid<Value: Hashable, Content: View>: View {
    let values: [Value]
    @Binding var selection: Value?
    @ViewBuilder let content: (Value) -> Content

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 0), spacing: SharpitSpacing.xs),
                count: min(values.count, 5)
            ),
            spacing: SharpitSpacing.xs
        ) {
            ForEach(values, id: \.self) { value in
                Button { selection = value } label: {
                    content(value)
                        .font(SharpitTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(
                            selection == value
                                ? SharpitColor.primaryForeground
                                : SharpitColor.foreground
                        )
                        .background(
                            selection == value
                                ? SharpitColor.primary
                                : SharpitColor.analysisSurfaceAlt,
                            in: RoundedRectangle(
                                cornerRadius: SharpitRadius.panel,
                                style: .continuous
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SummarySignal: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(SharpitColor.mutedForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .background(SharpitColor.analysisSurfaceAlt, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct ActivityRouteHero: View {
    let route: [V1ActivityCoordinate]
    let tone: Color

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var region: MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard
            let minLatitude = latitudes.min(),
            let maxLatitude = latitudes.max(),
            let minLongitude = longitudes.min(),
            let maxLongitude = longitudes.max()
        else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 45.764, longitude: 4.835),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        }

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(maxLatitude - minLatitude, 0.008) * 1.35,
                longitudeDelta: max(maxLongitude - minLongitude, 0.008) * 1.35
            )
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(initialPosition: .region(region), interactionModes: []) {
                MapPolyline(coordinates: coordinates)
                    .stroke(tone, lineWidth: 5)
                if let start = coordinates.first {
                    Annotation("Départ", coordinate: start) {
                        RoutePointMarker(color: .white, stroke: tone)
                    }
                }
                if let finish = coordinates.last {
                    Annotation("Arrivée", coordinate: finish) {
                        RoutePointMarker(color: tone, stroke: .white)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tracé GPS de l’activité, \(route.count) points")
    }
}

private struct ActivityRouteLoadingSurface: View {
    var body: some View {
        ZStack {
            SharpitColor.analysisSurfaceAlt
            LinearGradient(
                colors: [.clear, SharpitColor.analysisGrid],
                startPoint: .top,
                endPoint: .bottom
            )
            ProgressView()
                .tint(.secondary)
                .accessibilityLabel("Chargement de la carte")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Carte en cours de chargement")
    }
}

private struct RoutePointMarker: View {
    let color: Color
    let stroke: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 13, height: 13)
            .overlay(Circle().stroke(stroke, lineWidth: 3))
            .shadow(color: .black.opacity(0.2), radius: 3)
    }
}

private struct ContextChip: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(SharpitColor.mutedForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(SharpitElevatedColor.panelOnSheet, in: Capsule())
    }
}

private struct ActivityDetailLoading: View {
    let viewportHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [.clear, SharpitColor.analysisGrid],
                startPoint: .top,
                endPoint: .bottom
            )

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: viewportHeight * 0.62)

                    ActivityDetailLoadingSheet()
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityLabel("Chargement du détail")
    }
}

private struct ActivityDetailLoadingSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            HStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(SharpitColor.analysisSurfaceAlt)
                    .frame(width: 124, height: 16)
                Spacer()
                RoundedRectangle(cornerRadius: 8)
                    .fill(SharpitColor.analysisSurfaceAlt)
                    .frame(width: 104, height: 16)
            }

            RoundedRectangle(cornerRadius: 10)
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(maxWidth: 300, minHeight: 40)

            HStack(spacing: SharpitSpacing.xxs) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                        .fill(SharpitColor.analysisSurfaceAlt)
                        .frame(height: 92)
                }
            }

            RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                .fill(SharpitColor.analysisSurfaceAlt)
                .frame(height: 156)

            HStack(spacing: SharpitSpacing.xxs) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                        .fill(SharpitColor.analysisSurfaceAlt)
                        .frame(height: 92)
                }
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.lg)
        .padding(.bottom, SharpitSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(SharpitElevatedColor.sheet)
                .sharpitShadow(.panel)
        )
        .environment(\.sharpitElevation, .sheet)
        .redacted(reason: .placeholder)
    }
}

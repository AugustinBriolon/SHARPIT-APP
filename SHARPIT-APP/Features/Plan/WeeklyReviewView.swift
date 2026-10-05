import Charts
import Observation
import SwiftUI

/// The coach's review of the week (SharpIt Pro): the latest one written, or the way to write
/// the one for the week in progress.
@MainActor
@Observable
final class WeeklyReviewStore {
    enum Phase: Equatable {
        case loading
        case empty
        case loaded(V1WeeklyReview)
        case proRequired
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var isWriting = false
    /// Why the last « Écrire le bilan » failed, shown without losing the review on screen.
    private(set) var writeError: String?

    private let client: any WeeklyReviewServing
    private let tokenProvider: () async throws -> String

    init(client: any WeeklyReviewServing = WeeklyReviewClient(), tokenProvider: @escaping () async throws -> String) {
        self.client = client
        self.tokenProvider = tokenProvider
    }

    func load() async {
        do {
            let review = try await client.latestReview(token: try await tokenProvider())
            phase = review.map(Phase.loaded) ?? .empty
        } catch WeeklyReviewError.proRequired {
            phase = .proRequired
        } catch {
            phase = .failed(SharpitErrorGuidance.message(for: error, subject: "Le bilan"))
        }
    }

    /// Writes the review of the week in progress; it replaces the one on screen.
    func write() async {
        guard !isWriting else { return }
        isWriting = true
        writeError = nil
        defer { isWriting = false }
        do {
            let review = try await client.generateReview(token: try await tokenProvider())
            phase = .loaded(review)
        } catch WeeklyReviewError.proRequired {
            phase = .proRequired
        } catch SharpitAPIError.rateLimited {
            writeError = "Tu as demandé plusieurs bilans d'affilée. Réessaie dans une heure."
        } catch {
            writeError = SharpitErrorGuidance.message(for: error, subject: "Le bilan")
        }
    }
}

struct WeeklyReviewView: View {
    @State private var store: WeeklyReviewStore

    init(store: WeeklyReviewStore) {
        _store = State(initialValue: store)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                content
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle("Bilan de la semaine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .loaded = store.phase {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Task { await store.write() }
                        } label: {
                            Label("Refaire le bilan de cette semaine", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .disabled(store.isWriting)
                }
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        if store.isWriting {
            HStack(spacing: SharpitSpacing.xs) {
                ProgressView().controlSize(.small)
                Text("Le coach relit ta semaine…")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        if let writeError = store.writeError {
            Label(writeError, systemImage: "exclamationmark.triangle")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.signalRisk)
        }

        switch store.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, SharpitSpacing.xl)
        case .proRequired:
            SharpitProTeaser(
                title: "Bilan hebdomadaire",
                message: "Volume, charge, sommeil et récupération de la semaine, synthétisés par le coach — avec un plan pour la semaine suivante."
            )
        case .failed(let message):
            SharpitStateMessage.failed(message) { Task { await store.load() } }
        case .empty:
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                Text("Pas encore de bilan")
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)
                Text("Le coach relit ta semaine — volume, charge, sommeil, récupération — et prépare la suivante.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await store.write() }
                } label: {
                    Text("Écrire le bilan")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.primaryForeground)
                        .frame(maxWidth: .infinity)
                }
                .sharpitGlassButton(prominent: true)
                .tint(SharpitColor.primary)
                .disabled(store.isWriting)
            }
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
        case .loaded(let review):
            WeeklyReviewContent(review: review)
        }
    }
}

private struct WeeklyReviewContent: View {
    let review: V1WeeklyReview

    private var weekLabel: String {
        guard let date = TrainingDayId.date(review.weekStart) else { return "" }
        return "Semaine du " + date.sharpitFormatted(.dateTime.day().month(.wide))
    }

    var body: some View {
        let sections = WeeklyReviewSections(markdown: review.content)
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            Text(weekLabel)
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.foreground)

            if !(sections.wins + sections.watch + sections.mixed).isEmpty {
                ReviewSection(title: "Faits marquants") {
                    ForEach(sections.wins, id: \.self) { item in
                        ReviewHighlightCard(symbol: "checkmark.circle.fill", category: "Bien joué", tint: SharpitColor.signalRecovery, headline: item)
                    }
                    ForEach(sections.watch, id: \.self) { item in
                        ReviewHighlightCard(symbol: "exclamationmark.circle.fill", category: "À surveiller", tint: SharpitColor.signalCaution, headline: item)
                    }
                    ForEach(sections.mixed, id: \.self) { item in
                        ReviewHighlightCard(symbol: "circle.fill", category: "À retenir", tint: SharpitColor.mutedForeground, headline: item)
                    }
                }
            }

            if let stats = review.stats {
                ReviewSection(title: "Ta semaine en chiffres") {
                    WeeklyReviewMetrics(stats: stats)
                }
            }

            if !sections.nextWeek.isEmpty {
                ReviewSection(title: "La semaine prochaine") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sections.nextWeek.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                                Text("\(index + 1)")
                                    .font(SharpitTypography.cardTitle.monospacedDigit())
                                    .foregroundStyle(SharpitColor.primary)
                                    .frame(width: 18, alignment: .leading)
                                Text(item)
                                    .font(SharpitTypography.body)
                                    .foregroundStyle(SharpitColor.foreground)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, SharpitSpacing.sm)
                            if index < sections.nextWeek.count - 1 {
                                Rectangle().fill(SharpitColor.analysisGrid).frame(height: 1).padding(.leading, 30)
                            }
                        }
                    }
                    .padding(.horizontal, SharpitSpacing.cardPadding)
                    .sharpitSurface(.panel)
                }
            }

            if !sections.narrative.isEmpty {
                NavigationLink {
                    ScrollView {
                        SharpitMarkdownText(markdown: review.content)
                            .padding(SharpitSpacing.pageInset)
                    }
                    .background(SharpitCanvasBackground())
                    .navigationTitle(weekLabel)
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack {
                        Text("Lire le bilan complet")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(SharpitSpacing.cardPadding)
                    .sharpitSurface(.panel)
                }
                .buttonStyle(.sharpitPressable)
            }
        }
    }
}

/// A titled group, as the Health app lays out its summary.
private struct ReviewSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            content
        }
    }
}

/// One fact of the week, the way Health shows a highlight: a tinted category above a short,
/// bold sentence.
private struct ReviewHighlightCard: View {
    let symbol: String
    let category: String
    let tint: Color
    let headline: String

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Label(category, systemImage: symbol)
                .font(SharpitTypography.meta.weight(.semibold))
                .foregroundStyle(tint)
            Text(headline)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

/// The week's figures, one card each as Health draws a metric: a tinted name, the figure large
/// with its unit small, and the days as quiet bars with the average dashed across.
private struct WeeklyReviewMetrics: View {
    let stats: V1WeeklyStats

    var body: some View {
        VStack(spacing: SharpitSpacing.sm) {
            if let done = stats.sessionsDone {
                let planned = max(stats.sessionsPlanned ?? done, done)
                let ratio = planned > 0 ? Double(done) / Double(planned) : 1
                ReviewMetricCard(
                    symbol: "figure.run",
                    name: "Séances",
                    tint: WeeklyReviewTone.ratio(ratio),
                    value: Text("\(done)"),
                    unit: "sur \(planned) prévues"
                ) {
                    ProgressView(value: ratio).tint(WeeklyReviewTone.ratio(ratio))
                }
            }
            if let load = stats.totalLoad {
                ReviewMetricCard(
                    symbol: "bolt.fill",
                    name: "Charge",
                    tint: SharpitColor.primary,
                    value: Text("\(Int(load.rounded()))"),
                    unit: loadChange.map { "\($0 >= 0 ? "+" : "")\($0) % vs semaine passée" } ?? "cette semaine"
                ) {
                    if let daily = stats.dailyLoad, daily.contains(where: { $0 != nil }) {
                        ReviewDayBars(values: daily, tint: SharpitColor.primary)
                    }
                }
            }
            if let sleep = stats.sleep?.avgDurationMin, sleep > 0 {
                ReviewMetricCard(
                    symbol: "bed.double.fill",
                    name: "Sommeil",
                    tint: WeeklyReviewTone.sleep(minutes: sleep),
                    value: Text("\(Int(sleep) / 60)") + Text(" h ").font(SharpitTypography.cardTitle) + Text(String(format: "%02d", Int(sleep) % 60)),
                    unit: "en moyenne par nuit"
                ) {
                    if let daily = stats.dailySleepScore, daily.contains(where: { $0 != nil }) {
                        ReviewDayBars(values: daily, tint: WeeklyReviewTone.sleep(minutes: sleep))
                    }
                }
            }
            if let readiness = stats.recovery?.avgReadiness {
                ReviewMetricCard(
                    symbol: "heart.fill",
                    name: "Forme",
                    tint: WeeklyReviewTone.score(readiness),
                    value: Text("\(Int(readiness.rounded()))"),
                    unit: "en moyenne"
                ) { EmptyView() }
            }
            if let shares = stats.byType?.filter({ $0.durationMin > 0 }), !shares.isEmpty {
                ReviewSportShares(shares: shares)
            }
        }
    }

    private var loadChange: Int? {
        guard let load = stats.totalLoad, let previous = stats.prevTotalLoad, previous > 0 else { return nil }
        return Int(((load - previous) / previous * 100).rounded())
    }
}

private struct ReviewMetricCard<Detail: View>: View {
    let symbol: String
    let name: String
    let tint: Color
    let value: Text
    let unit: String
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Label(name, systemImage: symbol)
                .font(SharpitTypography.meta.weight(.semibold))
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                value
                    .font(SharpitTypography.gaugeScore)
                    .tracking(SharpitTypography.gaugeScoreTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text(unit)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            detail
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

/// Monday to Sunday as quiet bars in one tint, the average dashed across.
private struct ReviewDayBars: View {
    let values: [Double?]
    let tint: Color

    /// Distinct keys for the chart's categories; the axis shows their first letter.
    private static let days = ["Lu", "Ma", "Me", "Je", "Ve", "Sa", "Di"]

    private var average: Double? {
        let present = values.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
    }

    var body: some View {
        Chart {
            ForEach(Array(values.prefix(7).enumerated()), id: \.offset) { index, value in
                BarMark(x: .value("Jour", Self.days[index]), y: .value("Valeur", value ?? 0), width: .ratio(0.55))
                    .foregroundStyle(value == nil ? SharpitColor.analysisGrid : tint.opacity(0.85))
                    .cornerRadius(4)
            }
            if let average {
                RuleMark(y: .value("Moyenne", average))
                    .foregroundStyle(SharpitColor.mutedForeground.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let day = value.as(String.self) {
                        Text(day.prefix(1)).font(SharpitTypography.meta)
                    }
                }
            }
        }
        .frame(height: 72)
        .padding(.top, SharpitSpacing.xxs)
    }
}

/// Where the time went: one bar split by sport, then each sport with its sessions and minutes.
private struct ReviewSportShares: View {
    let shares: [V1WeeklyStats.SportShare]

    var body: some View {
        let total = shares.reduce(0) { $0 + $1.durationMin }
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Label("Temps par sport", systemImage: "chart.bar.fill")
                .font(SharpitTypography.meta.weight(.semibold))
                .foregroundStyle(SharpitColor.mutedForeground)
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(shares, id: \.type) { share in
                        Capsule()
                            .fill(tone(share.type))
                            .frame(width: max(6, geometry.size.width * share.durationMin / total - 2))
                    }
                }
            }
            .frame(height: 10)
            ForEach(shares, id: \.type) { share in
                HStack(spacing: SharpitSpacing.xs) {
                    Circle().fill(tone(share.type)).frame(width: 8, height: 8)
                    Text(V1ActivityType(rawValue: share.type)?.label ?? share.type.capitalized)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer()
                    Text("\(Int(share.durationMin)) min")
                        .font(SharpitTypography.instrument)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private func tone(_ type: String) -> Color {
        V1ActivityType(rawValue: type).map { SharpitSportTone.label(for: $0) } ?? SharpitColor.mutedForeground
    }
}

/// How a weekly figure reads, as a colour: good, to watch, low.
nonisolated enum WeeklyReviewTone {
    /// A 0…100 score (sleep, readiness).
    static func score(_ value: Double) -> Color {
        value >= 75 ? SharpitColor.signalRecovery : value >= 55 ? SharpitColor.signalCaution : SharpitColor.signalRisk
    }

    static func sleep(minutes: Double) -> Color {
        minutes >= 420 ? SharpitColor.signalRecovery : minutes >= 360 ? SharpitColor.signalCaution : SharpitColor.signalRisk
    }

    /// Sessions done against planned.
    static func ratio(_ value: Double) -> Color {
        value >= 0.8 ? SharpitColor.signalRecovery : value >= 0.5 ? SharpitColor.signalCaution : SharpitColor.signalRisk
    }
}

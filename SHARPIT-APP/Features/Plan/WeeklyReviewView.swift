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
            SharpitHaptics.play(.success)
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

    private var sections: WeeklyReviewSections { WeeklyReviewSections(markdown: review.content) }

    private var weekLabel: String {
        guard let date = TrainingDayId.date(review.weekStart) else { return "" }
        return "Semaine du " + date.sharpitFormatted(.dateTime.day().month(.wide))
    }

    var body: some View {
        let sections = sections
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitEyebrow(weekLabel)
            if let stats = review.stats {
                WeeklyReviewFigures(stats: stats)
                WeeklyReviewCharts(stats: stats)
            }
            if !sections.wins.isEmpty {
                WeeklyReviewList(title: "Ce qui a bien marché", items: sections.wins, symbol: "checkmark.circle.fill", tone: SharpitColor.signalRecovery)
            }
            if !sections.watch.isEmpty {
                WeeklyReviewList(title: "À surveiller", items: sections.watch, symbol: "exclamationmark.triangle.fill", tone: SharpitColor.signalCaution)
            }
            if !sections.mixed.isEmpty {
                WeeklyReviewList(title: "Points clés", items: sections.mixed, symbol: "circle.fill", tone: SharpitColor.mutedForeground)
            }
            if !sections.nextWeek.isEmpty {
                WeeklyReviewList(title: "La semaine prochaine", items: sections.nextWeek, symbol: "arrow.forward.circle.fill", tone: SharpitColor.primary)
            }
            if !sections.narrative.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                        ForEach(sections.narrative, id: \.title) { part in
                            SharpitMarkdownText(markdown: "### \(part.title)\n\n\(part.text)")
                        }
                    }
                    .padding(.top, SharpitSpacing.xs)
                } label: {
                    Text("Lire le bilan détaillé")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                }
                .tint(SharpitColor.mutedForeground)
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
            }
        }
    }
}

/// A short list on a card tinted by what it says: green for what went well, amber to watch.
private struct WeeklyReviewList: View {
    let title: String
    let items: [String]
    let symbol: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text(title)
                .font(SharpitTypography.cardTitle)
                .tracking(SharpitTypography.cardTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tone)
                    Text(item)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                .fill(tone.opacity(0.10))
        )
    }
}

/// The week's figures, each coloured by how it reads: done against planned, sleep, form.
private struct WeeklyReviewFigures: View {
    let stats: V1WeeklyStats

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SharpitSpacing.xs) {
            if let done = stats.sessionsDone {
                let planned = max(stats.sessionsPlanned ?? done, done)
                let ratio = planned > 0 ? Double(done) / Double(planned) : 1
                figure("Séances", value: "\(done) / \(planned)", tone: WeeklyReviewTone.ratio(ratio)) {
                    ProgressView(value: ratio).tint(WeeklyReviewTone.ratio(ratio))
                }
            }
            if let sleep = stats.sleep?.avgDurationMin, sleep > 0 {
                figure("Sommeil moyen", value: "\(Int(sleep) / 60) h \(String(format: "%02d", Int(sleep) % 60))", tone: WeeklyReviewTone.sleep(minutes: sleep)) { EmptyView() }
            }
            if let readiness = stats.recovery?.avgReadiness {
                figure("Forme moyenne", value: "\(Int(readiness.rounded()))", tone: WeeklyReviewTone.score(readiness)) { EmptyView() }
            }
            if let load = stats.totalLoad {
                figure("Charge", value: "\(Int(load.rounded()))", tone: SharpitColor.foreground) {
                    if let previous = stats.prevTotalLoad, previous > 0 {
                        let change = Int(((load - previous) / previous * 100).rounded())
                        Label("\(change >= 0 ? "+" : "")\(change) % vs semaine passée", systemImage: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
            }
        }
    }

    private func figure(_ label: String, value: String, tone: Color, @ViewBuilder detail: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SharpitFieldLabel(label)
            Text(value)
                .font(SharpitTypography.instrument)
                .foregroundStyle(tone)
            detail()
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(SharpitSpacing.sm)
        .sharpitSurface(.panel)
    }
}

/// Load and sleep day by day, and where the time went by sport.
private struct WeeklyReviewCharts: View {
    let stats: V1WeeklyStats

    private static let days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            if let load = stats.dailyLoad, load.contains(where: { $0 != nil }) {
                chart("Charge par jour", values: load) { _ in SharpitColor.primary }
            }
            if let sleep = stats.dailySleepScore, sleep.contains(where: { $0 != nil }) {
                chart("Sommeil par nuit", values: sleep) { WeeklyReviewTone.score($0) }
            }
            if let shares = stats.byType, shares.contains(where: { $0.durationMin > 0 }) {
                sports(shares.filter { $0.durationMin > 0 })
            }
        }
    }

    private func chart(_ title: String, values: [Double?], color: @escaping (Double) -> Color) -> some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel(title)
            Chart {
                ForEach(Array(values.prefix(7).enumerated()), id: \.offset) { index, value in
                    BarMark(
                        x: .value("Jour", Self.days[index]),
                        y: .value(title, value ?? 0)
                    )
                    .foregroundStyle(value.map(color) ?? SharpitColor.analysisGrid)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(SharpitTypography.meta) }
            }
            .frame(height: 96)
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private func sports(_ shares: [V1WeeklyStats.SportShare]) -> some View {
        let total = shares.reduce(0) { $0 + $1.durationMin }
        return VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitFieldLabel("Temps par sport")
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(shares, id: \.type) { share in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tone(share.type))
                            .frame(width: max(4, geometry.size.width * share.durationMin / total - 2))
                    }
                }
            }
            .frame(height: 12)
            ForEach(shares, id: \.type) { share in
                HStack(spacing: SharpitSpacing.xs) {
                    Circle().fill(tone(share.type)).frame(width: 8, height: 8)
                    Text(V1ActivityType(rawValue: share.type)?.label ?? share.type.capitalized)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer()
                    Text("\(share.count) · \(Int(share.durationMin)) min")
                        .font(SharpitTypography.meta.monospacedDigit())
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

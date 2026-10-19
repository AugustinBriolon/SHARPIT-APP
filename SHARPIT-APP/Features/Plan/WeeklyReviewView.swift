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
    /// « Préparer ma semaine »: the review's natural next step (ADR-095); nil where it cannot open.
    private let onPrepareWeek: (() -> Void)?

    init(store: WeeklyReviewStore, onPrepareWeek: (() -> Void)? = nil) {
        _store = State(initialValue: store)
        self.onPrepareWeek = onPrepareWeek
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                content
                if case .loaded = store.phase, let onPrepareWeek {
                    SharpitPrimaryButton(title: "Préparer ma semaine", trailingSymbol: "arrow.right", action: onPrepareWeek)
                        .padding(.top, SharpitSpacing.sm)
                }
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
        VStack(alignment: .leading, spacing: SharpitSpacing.section) {
            WeeklyReviewHero(weekLabel: weekLabel, stats: review.stats)

            let highlights = ReviewHighlight.all(from: sections)
            if !highlights.isEmpty {
                ReviewCard(title: "Faits marquants", symbol: "list.star") {
                    SharpitInsetGroup {
                        ForEach(highlights) { highlight in
                            ReviewHighlightRow(highlight: highlight)
                        }
                    }
                }
            }

            if let stats = review.stats {
                WeeklyReviewMetrics(stats: stats)
            }

            if !sections.nextWeek.isEmpty {
                ReviewCard(title: "La semaine prochaine", symbol: "arrow.forward") {
                    SharpitInsetGroup {
                        ForEach(Array(sections.nextWeek.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                                SharpitNumberChip(number: index + 1)
                                Text(item)
                                    .font(SharpitTypography.body)
                                    .foregroundStyle(SharpitColor.foreground)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 4)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, SharpitSpacing.rowPaddingX)
                            .padding(.vertical, SharpitSpacing.sm)
                            .sharpitSurface(.row)
                        }
                    }
                }
            }

            if !sections.narrative.isEmpty {
                NavigationLink {
                    ScrollView {
                        SharpitMarkdownText(markdown: review.content)
                            .textSelection(.enabled)
                            .padding(SharpitSpacing.pageInset)
                    }
                    .background(SharpitCanvasBackground())
                    .navigationTitle(weekLabel)
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack(spacing: SharpitSpacing.xs) {
                        Text("Lire le bilan complet")
                            .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .headline))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(maxWidth: .infinity)
                    .frame(height: SharpitTokens.controlHeight)
                    .sharpitConcentricBackground(SharpitColor.chipSurface, minimum: SharpitRadius.control)
                }
                .buttonStyle(.sharpitPressable)
            }
        }
    }
}

/// The week at a glance, the one ink card of the page: the lime tile, the week, then its three
/// figures — sessions against the plan, load, sleep — big and white.
private struct WeeklyReviewHero: View {
    let weekLabel: String
    let stats: V1WeeklyStats?

    private var ink: Color { SharpitColor.inkSurfaceForeground }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "calendar")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(SharpitColor.highlightForeground)
                    .frame(width: SharpitTokens.tileSize, height: SharpitTokens.tileSize)
                    .sharpitConcentricBackground(SharpitColor.highlight, minimum: SharpitRadius.tile)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(weekLabel)
                        .font(SharpitTypography.cardTitle)
                        .foregroundStyle(ink)
                    Text("Relue par le coach")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(ink.opacity(0.6))
                }
                Spacer(minLength: 0)
            }

            if let figures = stats.map(ReviewHeroFigure.all), !figures.isEmpty {
                HStack(alignment: .top, spacing: SharpitSpacing.md) {
                    ForEach(figures) { figure in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(figure.value)
                                    .font(SharpitTypography.system(size: 28, weight: .heavy, relativeTo: .title, digits: true))
                                    .tracking(-0.6)
                                    .foregroundStyle(ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                if let unit = figure.unit {
                                    Text(unit)
                                        .font(SharpitTypography.system(size: 15, weight: .medium, relativeTo: .subheadline))
                                        .foregroundStyle(ink.opacity(0.6))
                                }
                            }
                            Text(figure.caption)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(ink.opacity(0.6))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
    }
}

/// A figure of the hero: « 5 /6 Séances », « 412 Charge », « 7 h 12 Sommeil ».
struct ReviewHeroFigure: Identifiable, Equatable {
    let caption: String
    let value: String
    let unit: String?
    var id: String { caption }

    static func all(from stats: V1WeeklyStats) -> [ReviewHeroFigure] {
        var figures: [ReviewHeroFigure] = []
        if let done = stats.sessionsDone {
            let planned = max(stats.sessionsPlanned ?? done, done)
            figures.append(.init(caption: "Séances", value: "\(done)", unit: "/\(planned)"))
        }
        if let load = stats.totalLoad {
            figures.append(.init(caption: "Charge", value: "\(Int(load.rounded()))", unit: nil))
        }
        if let sleep = stats.sleep?.avgDurationMin, sleep > 0 {
            let minutes = Int(sleep.rounded())
            figures.append(.init(caption: "Sommeil", value: "\(minutes / 60) h", unit: String(format: "%02d", minutes % 60)))
        }
        return figures
    }
}

/// A white card of the review: the shared header, then its body.
private struct ReviewCard<Content: View>: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitCardHeader(title: title, symbol: symbol, subtitle: subtitle, showsChevron: false)
            content
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

/// One fact of the week, its kind told by the mark: a lime check for what went well, a caution
/// mark for what to watch, a neutral dot for the rest.
struct ReviewHighlight: Identifiable, Equatable {
    enum Kind: Equatable { case win, watch, note }
    let kind: Kind
    let text: String
    var id: String { "\(kind)-\(text)" }

    static func all(from sections: WeeklyReviewSections) -> [ReviewHighlight] {
        sections.wins.map { .init(kind: .win, text: $0) }
            + sections.watch.map { .init(kind: .watch, text: $0) }
            + sections.mixed.map { .init(kind: .note, text: $0) }
    }
}

private struct ReviewHighlightRow: View {
    let highlight: ReviewHighlight

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
            mark
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(highlight.kind == .watch ? SharpitColor.signalCaution : SharpitColor.mutedForeground)
                Text(highlight.text)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SharpitSpacing.rowPaddingX)
        .padding(.vertical, SharpitSpacing.sm)
        .sharpitSurface(.row)
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch highlight.kind {
        case .win: "Bien joué"
        case .watch: "À surveiller"
        case .note: "À retenir"
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch highlight.kind {
        case .win:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(SharpitColor.highlightForeground)
                .frame(width: 26, height: 26)
                .sharpitConcentricBackground(SharpitColor.highlight, minimum: 8)
        case .watch:
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .sharpitConcentricBackground(SharpitColor.signalCaution, minimum: 8)
        case .note:
            Image(systemName: "circle.fill")
                .font(.system(size: 6))
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(width: 26, height: 26)
                .sharpitConcentricBackground(SharpitColor.chipSurface, minimum: 8)
        }
    }
}

/// The week's figures as white cards in pairs — sessions, load, sleep, form — each with its
/// days as ink bars and the average dashed across; then where the time went, by sport.
private struct WeeklyReviewMetrics: View {
    let stats: V1WeeklyStats

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text("En chiffres")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: SharpitSpacing.sm), GridItem(.flexible())], spacing: SharpitSpacing.sm) {
                if let done = stats.sessionsDone {
                    let planned = max(stats.sessionsPlanned ?? done, done)
                    let ratio = planned > 0 ? Double(done) / Double(planned) : 1
                    ReviewMetricCard(name: "Séances", value: "\(done)", unit: "sur \(planned)", tone: WeeklyReviewTone.ratio(ratio)) {
                        SharpitBarTrack(fraction: ratio).frame(height: 6)
                    }
                }
                if let load = stats.totalLoad {
                    ReviewMetricCard(name: "Charge", value: "\(Int(load.rounded()))", unit: loadChange.map { "\($0 >= 0 ? "+" : "−")\(abs($0)) %" }) {
                        if let daily = stats.dailyLoad, daily.contains(where: { $0 != nil }) {
                            ReviewDayBars(values: daily)
                        }
                    }
                }
                if let sleep = stats.sleep?.avgDurationMin, sleep > 0 {
                    let minutes = Int(sleep.rounded())
                    ReviewMetricCard(name: "Sommeil", value: "\(minutes / 60) h \(String(format: "%02d", minutes % 60))", unit: nil, tone: WeeklyReviewTone.sleep(minutes: sleep)) {
                        if let daily = stats.dailySleepScore, daily.contains(where: { $0 != nil }) {
                            ReviewDayBars(values: daily)
                        }
                    }
                }
                if let readiness = stats.recovery?.avgReadiness {
                    ReviewMetricCard(name: "Forme", value: "\(Int(readiness.rounded()))", unit: "/100", tone: WeeklyReviewTone.score(readiness)) {
                        SharpitBarTrack(fraction: readiness / 100, tone: SharpitColor.foreground).frame(height: 6)
                    }
                }
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
    let name: String
    let value: String
    let unit: String?
    var tone: Color = SharpitColor.foreground
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Text(name)
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.mutedForeground)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(SharpitTypography.gaugeScore)
                    .tracking(SharpitTypography.gaugeScoreTracking)
                    .foregroundStyle(tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            detail
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(SharpitSpacing.md)
        .sharpitSurface(.panel)
    }
}

/// Monday to Sunday as ink bars, the strongest day lime, the average dashed across.
private struct ReviewDayBars: View {
    let values: [Double?]

    private static let days = ["Lu", "Ma", "Me", "Je", "Ve", "Sa", "Di"]

    private var average: Double? {
        let present = values.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
    }

    private var peak: Double? { values.compactMap { $0 }.max() }

    var body: some View {
        Chart {
            ForEach(Array(values.prefix(7).enumerated()), id: \.offset) { index, value in
                BarMark(x: .value("Jour", Self.days[index]), y: .value("Valeur", value ?? 0), width: .ratio(0.55))
                    .foregroundStyle(value == nil ? SharpitColor.track : value == peak ? SharpitColor.highlight : SharpitColor.foreground)
                    .cornerRadius(3)
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
                        Text(day.prefix(1)).font(.system(size: 10, weight: .medium))
                    }
                }
            }
        }
        .frame(height: 52)
    }
}

/// Where the time went: each sport as an inset row — its tile, its sessions, its minutes and
/// its share as a bar.
private struct ReviewSportShares: View {
    let shares: [V1WeeklyStats.SportShare]

    var body: some View {
        let total = max(shares.reduce(0) { $0 + $1.durationMin }, 1)
        ReviewCard(title: "Temps par sport", symbol: "stopwatch") {
            SharpitInsetGroup {
                ForEach(shares, id: \.type) { share in
                    // The server names some sports by key, others in words; both get their glyph.
                    let known = V1ActivityType(rawValue: share.type)
                    HStack(spacing: SharpitSpacing.sm) {
                        SharpitSportBadge(type: known ?? V1ActivityType(sportLabel: share.type), size: 32)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(known?.label ?? share.type.capitalized)
                                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body))
                                    .foregroundStyle(SharpitColor.foreground)
                                Text(share.count == 1 ? "1 séance" : "\(share.count) séances")
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                                Spacer(minLength: SharpitSpacing.xs)
                                SharpitRowFigure(value: "\(Int(share.durationMin.rounded()))", unit: "min")
                            }
                            SharpitBarTrack(fraction: share.durationMin / total, tone: SharpitColor.foreground)
                                .frame(height: 4)
                        }
                    }
                    .padding(.horizontal, SharpitSpacing.rowPaddingX)
                    .padding(.vertical, SharpitSpacing.sm)
                    .sharpitSurface(.row)
                }
            }
        }
    }
}

/// How a weekly figure reads: ink when it holds (ADR-085), caution to watch, risk when low.
nonisolated enum WeeklyReviewTone {
    /// A 0…100 score (sleep, readiness).
    static func score(_ value: Double) -> Color {
        value >= 75 ? SharpitColor.foreground : value >= 55 ? SharpitColor.signalCaution : SharpitColor.signalRisk
    }

    static func sleep(minutes: Double) -> Color {
        minutes >= 420 ? SharpitColor.foreground : minutes >= 360 ? SharpitColor.signalCaution : SharpitColor.signalRisk
    }

    /// Sessions done against planned.
    static func ratio(_ value: Double) -> Color {
        value >= 0.8 ? SharpitColor.foreground : value >= 0.5 ? SharpitColor.signalCaution : SharpitColor.signalRisk
    }
}

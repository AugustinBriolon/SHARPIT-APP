import Charts
import Observation
import StoreKit
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
            phase = .failed(SharpitErrorGuidance.message(for: error, subject: String(localized: "Le bilan")))
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
            writeError = String(localized: "Tu as demandé plusieurs bilans d'affilée. Réessaie dans une heure.")
        } catch {
            writeError = SharpitErrorGuidance.message(for: error, subject: String(localized: "Le bilan"))
        }
    }
}

struct WeeklyReviewView: View {
    @State private var store: WeeklyReviewStore
    @Environment(\.requestReview) private var requestReview
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
            }
            .padding(.horizontal, 24)
            .padding(.vertical, SharpitSpacing.md)
        }
        .cliniqueSheet(wash: .good, height: 220)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if case .loaded = store.phase, let onPrepareWeek {
                Button(action: onPrepareWeek) { Text("Préparer ma semaine").frame(maxWidth: .infinity) }
                    .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                    .padding(.horizontal, 16)
                    .padding(.vertical, SharpitSpacing.xs)
                    .background(SharpitColor.card)
            }
        }
        .navigationTitle("Bilan de la semaine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The page names itself: « Bilan du … ».
            ToolbarItem(placement: .principal) { Text("") }
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
        // A full week is a win the screen already says: the one moment here to ask for a rating.
        .onChange(of: isFullWeek) { _, full in
            if full { ReviewPrompt.askAfterWin(requestReview) }
        }
    }

    private var isFullWeek: Bool {
        guard case .loaded(let review) = store.phase else { return false }
        return WeeklyReviewReadout.isFull(review.stats)
    }

    @ViewBuilder
    private var content: some View {
        if store.isWriting {
            HStack(spacing: SharpitSpacing.xs) {
                ProgressView().controlSize(.small)
                Text("Le coach relit ta semaine…")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
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
                title: String(localized: "Bilan hebdomadaire"),
                message: String(localized: "Volume, charge, sommeil et récupération de la semaine, synthétisés par le coach, avec un plan pour la semaine suivante.")
            )
        case .failed(let message):
            SharpitStateMessage.failed(message) { Task { await store.load() } }
        case .empty:
            VStack(alignment: .leading, spacing: 14) {
                Text("Pas encore de bilan")
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                Text("Le coach relit ta semaine (volume, charge, sommeil, récupération) et prépare la suivante.")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Écrire le bilan") { Task { await store.write() } }
                    .buttonStyle(CliniqueButtonStyle(kind: .primary))
                    .disabled(store.isWriting)
            }
            .cliniqueCard()
        case .loaded(let review):
            WeeklyReviewContent(review: review)
        }
    }
}

/// The review on its mock-up (`docs/adr/0035`): how the week stood as a pill, « Bilan du … », the
/// week's three figures between hairlines, the time by sport as a table, what to keep, the figures
/// behind it, the week ahead in a bordered card, then the full text on its own page.
private struct WeeklyReviewContent: View {
    let review: V1WeeklyReview

    var body: some View {
        let sections = WeeklyReviewSections(markdown: review.content)
        VStack(alignment: .leading, spacing: 26) {
            VStack(spacing: 10) {
                if let standing = WeeklyReviewReadout.standing(review.stats) {
                    CliniqueStatusPill(standing.text, status: standing.status)
                }
                Text(WeeklyReviewReadout.title(weekStart: review.weekStart))
                    .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title, digits: true))
                    .tracking(-0.4)
                    .foregroundStyle(SharpitColor.foreground)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("Relue par le coach")
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.slate)
            }
            .frame(maxWidth: .infinity)

            if let figures = review.stats.map(WeeklyReviewReadout.strip), !figures.isEmpty {
                VStack(spacing: 0) {
                    CliniqueDivider()
                    HStack(spacing: 0) {
                        ForEach(Array(figures.enumerated()), id: \.element.id) { index, figure in
                            if index > 0 { Rectangle().fill(SharpitColor.divider).frame(width: 1, height: 34) }
                            VStack(spacing: 4) {
                                Text(figure.caption)
                                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
                                    .foregroundStyle(SharpitColor.slate)
                                (Text(figure.value).font(SharpitTypography.system(size: 19, weight: .semibold, relativeTo: .title3, digits: true)).foregroundStyle(SharpitColor.foreground)
                                    + Text(figure.unit.map { " \($0)" } ?? "").font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote, digits: true)).foregroundStyle(SharpitColor.slate))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.vertical, 14)
                    CliniqueDivider()
                }
            }

            if let shares = review.stats?.byType?.filter({ $0.durationMin > 0 }), !shares.isEmpty {
                ReviewSportShares(shares: shares)
            }

            let highlights = ReviewHighlight.all(from: sections)
            if !highlights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ReviewSectionTitle(String(localized: "À retenir"))
                    ForEach(highlights) { highlight in
                        ReviewHighlightRow(highlight: highlight)
                    }
                }
            }

            if let stats = review.stats {
                WeeklyReviewMetrics(stats: stats)
            }

            if !sections.nextWeek.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("La semaine qui vient")
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                        .foregroundStyle(SharpitColor.slate)
                    ForEach(Array(sections.nextWeek.enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                            .foregroundStyle(SharpitColor.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .cliniqueCard()
            }

            if !sections.narrative.isEmpty {
                NavigationLink {
                    ScrollView {
                        SharpitMarkdownText(markdown: review.content)
                            .textSelection(.enabled)
                            .padding(24)
                    }
                    .background(SharpitColor.card)
                    .navigationTitle(WeeklyReviewReadout.title(weekStart: review.weekStart))
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Text("Lire le bilan complet").frame(maxWidth: .infinity)
                }
                .buttonStyle(CliniqueButtonStyle(kind: .outline, isLarge: true))
            }
        }
    }
}

/// A section's name on the sheet.
private struct ReviewSectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(SharpitTypography.sectionTitle)
            .tracking(SharpitTypography.sectionTitleTracking)
            .foregroundStyle(SharpitColor.foreground)
            .accessibilityAddTraits(.isHeader)
    }
}

/// How the review words the week's frame.
nonisolated enum WeeklyReviewReadout {
    /// « Bilan du 3 au 9 novembre », the week's seven days from its Monday.
    @MainActor static func title(weekStart: String, locale: Locale = SharpitLocale.current) -> String {
        guard let start = TrainingDayId.date(weekStart),
              let end = Calendar.current.date(byAdding: .day, value: 6, to: start) else { return String(localized: "Bilan de la semaine") }
        let sameMonth = Calendar.current.component(.month, from: start) == Calendar.current.component(.month, from: end)
        let from = start.formatted((sameMonth ? Date.FormatStyle.dateTime.day() : .dateTime.day().month(.wide)).locale(locale))
        let to = end.formatted(.dateTime.day().month(.wide).locale(locale))
        return String(localized: "Bilan du \(from) au \(to)")
    }

    /// Every planned session done.
    static func isFull(_ stats: V1WeeklyStats?) -> Bool {
        guard let done = stats?.sessionsDone else { return false }
        let planned = max(stats?.sessionsPlanned ?? done, done)
        return planned > 0 && done >= planned
    }

    /// How full the week was against its plan; nil when the sessions are not counted.
    static func standing(_ stats: V1WeeklyStats?) -> (text: String, status: CliniqueStatus)? {
        guard let done = stats?.sessionsDone else { return nil }
        let planned = max(stats?.sessionsPlanned ?? done, done)
        guard planned > 0 else { return nil }
        if isFull(stats) { return (String(localized: "Semaine pleine"), .good) }
        return Double(done) / Double(planned) >= 0.5
            ? (String(localized: "Semaine presque pleine"), .good)
            : (String(localized: "Semaine légère"), .watch)
    }

    /// The strip under the title: sessions against the plan, the volume, the load.
    static func strip(_ stats: V1WeeklyStats) -> [ReviewHeroFigure] {
        var figures: [ReviewHeroFigure] = []
        if let done = stats.sessionsDone {
            let planned = max(stats.sessionsPlanned ?? done, done)
            figures.append(.init(caption: String(localized: "Séances"), value: "\(done)", unit: "/ \(planned)"))
        }
        if let minutes = stats.totalDurationMin, minutes > 0 {
            let whole = Int(minutes.rounded())
            figures.append(.init(caption: String(localized: "Volume"), value: "\(whole / 60) h \(String(format: "%02d", whole % 60))", unit: nil))
        }
        if let load = stats.totalLoad {
            figures.append(.init(caption: String(localized: "Charge"), value: "\(Int(load.rounded()))", unit: nil))
        }
        return figures
    }
}

/// A figure of the strip: « 5 / 6 Séances », « 9 h 10 Volume », « 412 Charge ».
struct ReviewHeroFigure: Identifiable, Equatable {
    let caption: String
    let value: String
    let unit: String?
    var id: String { caption }
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
        Text(highlight.text)
            .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
            .foregroundStyle(SharpitColor.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 18)
            .overlay(alignment: .leading) {
                Capsule().fill(tone).frame(width: 4).padding(.vertical, 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) : \(highlight.text)")
    }

    private var label: String {
        switch highlight.kind {
        case .win: String(localized: "Bien joué")
        case .watch: String(localized: "À surveiller")
        case .note: String(localized: "À retenir")
        }
    }

    private var tone: Color {
        switch highlight.kind {
        case .win: CliniqueStatus.good.mark
        case .watch: CliniqueStatus.watch.mark
        case .note: SharpitColor.outline
        }
    }
}

/// The figures behind the week as lines — the load against the week before with its days as
/// bars, the nights, the form.
private struct WeeklyReviewMetrics: View {
    let stats: V1WeeklyStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ReviewSectionTitle(String(localized: "En chiffres"))
            if let load = stats.totalLoad {
                row(String(localized: "Charge"), "\(Int(load.rounded()))", note: loadChange.map { String(localized: "\($0 >= 0 ? "+" : "−")\(abs($0)) % sur la semaine d'avant") })
                if let daily = stats.dailyLoad, daily.contains(where: { $0 != nil }) {
                    ReviewDayBars(values: daily).padding(.bottom, 12)
                }
            }
            if let sleep = stats.sleep?.avgDurationMin, sleep > 0 {
                let minutes = Int(sleep.rounded())
                CliniqueDivider()
                row(String(localized: "Sommeil moyen"), "\(minutes / 60) h \(String(format: "%02d", minutes % 60))", tone: WeeklyReviewTone.sleep(minutes: sleep))
            }
            if let readiness = stats.recovery?.avgReadiness {
                CliniqueDivider()
                row(String(localized: "Forme moyenne"), "\(Int(readiness.rounded())) / 100", tone: WeeklyReviewTone.score(readiness))
            }
        }
    }

    private func row(_ label: String, _ value: String, note: String? = nil, tone: Color = SharpitColor.foreground) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                if let note {
                    Text(note)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                }
            }
            Spacer(minLength: SharpitSpacing.xs)
            Text(value)
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(tone)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var loadChange: Int? {
        guard let load = stats.totalLoad, let previous = stats.prevTotalLoad, previous > 0 else { return nil }
        return Int(((load - previous) / previous * 100).rounded())
    }
}

/// Monday to Sunday as bars in the recovery hue, the strongest day full, the average dashed across.
private struct ReviewDayBars: View {
    let values: [Double?]

    private static let days = [String(localized: "Lu"), String(localized: "Ma"), String(localized: "Me"), String(localized: "Je"), String(localized: "Ve"), String(localized: "Sa"), String(localized: "Di")]

    private var average: Double? {
        let present = values.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
    }

    private var peak: Double? { values.compactMap { $0 }.max() }

    var body: some View {
        Chart {
            ForEach(Array(values.prefix(7).enumerated()), id: \.offset) { index, value in
                BarMark(x: .value(String(localized: "Jour"), Self.days[index]), y: .value(String(localized: "Valeur"), value ?? 0), width: .ratio(0.55))
                    .foregroundStyle(value == nil ? SharpitColor.divider : value == peak ? SharpitColor.pillarRecovery : SharpitColor.pillarRecovery.opacity(0.35))
                    .cornerRadius(3)
            }
            if let average {
                RuleMark(y: .value(String(localized: "Moyenne"), average))
                    .foregroundStyle(SharpitColor.slate.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let day = value.as(String.self) {
                        Text(day.prefix(1)).font(.system(size: 10, weight: .regular))
                    }
                }
            }
        }
        .frame(height: 52)
    }
}

/// Where the time went, as a table: each sport, its sessions, its time.
private struct ReviewSportShares: View {
    let shares: [V1WeeklyStats.SportShare]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sport").frame(maxWidth: .infinity, alignment: .leading)
                Text("Séances").frame(width: 80, alignment: .leading)
                Text("Temps").frame(width: 80, alignment: .trailing)
            }
            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote))
            .foregroundStyle(SharpitColor.slate)
            .padding(.bottom, 8)
            ForEach(shares, id: \.type) { share in
                CliniqueDivider()
                // The server names some sports by key, others in words.
                let minutes = Int(share.durationMin.rounded())
                HStack {
                    Text(V1ActivityType(rawValue: share.type)?.label ?? share.type.capitalized)
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(share.count)")
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                        .frame(width: 80, alignment: .leading)
                    Text(minutes >= 60 ? "\(minutes / 60) h \(String(format: "%02d", minutes % 60))" : "\(minutes) min")
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout, digits: true))
                        .frame(width: 80, alignment: .trailing)
                }
                .foregroundStyle(SharpitColor.foreground)
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
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

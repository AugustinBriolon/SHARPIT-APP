import Charts
import SwiftUI

/// « Progression » of one exercise, pushed from its card in the guided session: its picture and
/// name over `ExerciseProgressionContent`.
struct ExerciseProgressionPage: View {
    let name: String
    let tokenProvider: () async throws -> String
    var preloaded: [V1ExerciseSession]?

    /// `preloaded` skips the read: the Debug screen demo, which has no server.
    init(name: String, tokenProvider: @escaping () async throws -> String, preloaded: [V1ExerciseSession]? = nil) {
        self.name = name
        self.tokenProvider = tokenProvider
        self.preloaded = preloaded
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                if let gif = ExerciseMediaCatalog.gifURL(name: name) {
                    GuidedExerciseMediaView(url: gif, height: 180)
                    Text(ExerciseMediaCatalog.attribution)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.slate)
                }
                Text(name)
                    .font(SharpitTypography.system(size: 28, weight: .semibold, relativeTo: .title))
                    .tracking(-0.5)
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                ExerciseProgressionContent(name: name, tokenProvider: tokenProvider, preloaded: preloaded)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .navigationTitle("Progression")
    }
}

/// The days an exercise was done: the best load (or the longest hold) of each as a line, then
/// every day's sets, newest first. Read from the sets already logged
/// (`/api/v1/strength-exercises/progression`, under each of the exercise's spellings). Laid in a
/// page that scrolls: its own page, or the « Historique » of the exercise's sheet.
struct ExerciseProgressionContent: View {
    let name: String
    let tokenProvider: () async throws -> String

    @State private var phase: Phase

    init(name: String, tokenProvider: @escaping () async throws -> String, preloaded: [V1ExerciseSession]? = nil) {
        self.name = name
        self.tokenProvider = tokenProvider
        _phase = State(initialValue: preloaded.map(Phase.loaded) ?? .loading)
    }

    enum Phase: Equatable {
        case loading
        case loaded([V1ExerciseSession])
        case failed(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            case let .failed(message):
                SharpitStateMessage.failed(message) { Task { await load() } }
                    .embedded()
            case let .loaded(sessions):
                content(sessions)
            }
        }
        .task {
            guard phase == .loading else { return }
            await load()
        }
    }

    private func content(_ sessions: [V1ExerciseSession]) -> some View {
        let points = ExerciseProgressionReadout.points(sessions)
        return VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            if let change = ExerciseProgressionReadout.change(points) {
                Text(change)
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
            if points.count >= 2 {
                chart(points)
            }
            if sessions.isEmpty {
                Text("Aucune série enregistrée sur cet exercice.")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    CliniqueDivider()
                    ForEach(sessions.reversed()) { session in
                        sessionRow(session)
                        CliniqueDivider()
                    }
                }
            }
        }
    }

    private func chart(_ points: [ExerciseProgressionReadout.Point]) -> some View {
        Chart(points) { point in
            LineMark(x: .value("Jour", point.date), y: .value("Meilleur", point.value))
                .foregroundStyle(SharpitChartStyle.line)
                .lineStyle(StrokeStyle(lineWidth: SharpitChartStyle.lineWidth, lineCap: .round, lineJoin: .round))
            PointMark(x: .value("Jour", point.date), y: .value("Meilleur", point.value))
                .symbol { SharpitChartPoint() }
        }
        // A load read from zero flattens every change; the points keep clear of the edges.
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXScale(range: .plotDimension(padding: 12))
        .sharpitChartAxes()
        .frame(height: 180)
        .accessibilityLabel(ExerciseProgressionReadout.change(points) ?? String(localized: "Progression"))
    }

    private func sessionRow(_ session: V1ExerciseSession) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            Text(ExerciseProgressionReadout.day(session.date))
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline, digits: true))
                .foregroundStyle(SharpitColor.slate)
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(ExerciseProgressionReadout.lines(session).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                        .foregroundStyle(SharpitColor.foreground)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        do {
            phase = .loaded(try await StrengthLibraryStore.shared.progression(of: name, tokenProvider: tokenProvider))
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(SharpitErrorGuidance.message(for: error, subject: String(localized: "La progression")))
        }
    }
}

/// How an exercise's days read on its progression page.
enum ExerciseProgressionReadout {
    struct Point: Identifiable, Equatable {
        let date: Date
        let value: Double
        let isHold: Bool
        var id: Date { date }
    }

    /// One point a day: the best load, or the longest hold for an exercise never loaded.
    static func points(_ sessions: [V1ExerciseSession]) -> [Point] {
        let loaded = sessions.contains { ($0.bestWeightKg ?? 0) > 0 }
        return sessions.compactMap { session in
            guard let date = APIDate.day(session.date) else { return nil }
            if loaded {
                guard let kg = session.bestWeightKg, kg > 0 else { return nil }
                return Point(date: date, value: kg, isHold: false)
            }
            guard let seconds = session.bestDurationSec, seconds > 0 else { return nil }
            return Point(date: date, value: Double(seconds), isHold: true)
        }
    }

    /// « 55 kg → 65 kg depuis le 1 oct. », nil with fewer than two days to compare.
    static func change(_ points: [Point]) -> String? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        let since = first.date.formatted(.dateTime.day().month(.abbreviated))
        return String(localized: "\(figure(first)) → \(figure(last)) depuis le \(since)")
    }

    static func figure(_ point: Point) -> String {
        point.isHold ? PlannedSessionFormat.durationSeconds(Int(point.value)) : GuidedStrengthSetTarget.kilograms(point.value)
    }

    /// « 8 nov. »
    static func day(_ text: String) -> String {
        APIDate.day(text)?.formatted(.dateTime.day().month(.abbreviated)) ?? text
    }

    /// Each block of sets as the history writes it: « 3 × 8 · 60 kg ».
    static func lines(_ session: V1ExerciseSession) -> [String] {
        session.blocks.map {
            StrengthHistoryReadout.block(sets: $0.sets, reps: $0.reps, weightKg: $0.weightKg, durationSec: $0.durationSec)
        }
    }
}

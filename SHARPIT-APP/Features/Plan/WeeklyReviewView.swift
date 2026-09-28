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

    private var weekLabel: String {
        guard let date = TrainingDayId.date(review.weekStart) else { return "" }
        return "Semaine du " + date.sharpitFormatted(.dateTime.day().month(.wide))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitEyebrow(weekLabel)
            if let stats = review.stats {
                WeeklyReviewFigures(stats: stats)
            }
            SharpitMarkdownText(markdown: review.content)
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
        }
    }
}

/// The figures the coach read, in a grid — only those the week has.
private struct WeeklyReviewFigures: View {
    let stats: V1WeeklyStats

    private var figures: [(label: String, value: String)] {
        var list: [(String, String)] = []
        if let done = stats.sessionsDone {
            let planned = stats.sessionsPlanned.map { " / \($0)" } ?? ""
            list.append(("Séances", "\(done)\(planned)"))
        }
        if let minutes = stats.totalDurationMin, minutes > 0 {
            list.append(("Durée", minutes >= 60 ? "\(Int(minutes) / 60) h \(String(format: "%02d", Int(minutes) % 60))" : "\(Int(minutes)) min"))
        }
        if let load = stats.totalLoad {
            var value = "\(Int(load.rounded()))"
            if let previous = stats.prevTotalLoad, previous > 0 {
                let change = Int(((load - previous) / previous * 100).rounded())
                value += change >= 0 ? " (+\(change) %)" : " (\(change) %)"
            }
            list.append(("Charge", value))
        }
        if let sleep = stats.sleep?.avgDurationMin, sleep > 0 {
            list.append(("Sommeil moyen", "\(Int(sleep) / 60) h \(String(format: "%02d", Int(sleep) % 60))"))
        }
        if let readiness = stats.recovery?.avgReadiness {
            list.append(("Forme moyenne", "\(Int(readiness.rounded()))"))
        }
        return list
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SharpitSpacing.xs) {
            ForEach(figures, id: \.label) { figure in
                VStack(alignment: .leading, spacing: 2) {
                    SharpitFieldLabel(figure.label)
                    Text(figure.value)
                        .font(SharpitTypography.instrument)
                        .foregroundStyle(SharpitColor.foreground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.sm)
                .sharpitSurface(.panel)
            }
        }
    }
}

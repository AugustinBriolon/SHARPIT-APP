import SwiftData
import SwiftUI

struct TodayView: View {
    @State private var store: TodayStore
    @State private var weather = LocationWeatherService()

    /// Kept so an activity opened from here can load itself. Nil in previews and
    /// fixtures, where a done session has nothing to fetch.
    private let tokenProvider: (() async throws -> String)?

    /// Nil without a token: the mode chip and the journal both write, and a control
    /// that cannot save is worse than no control.
    @State private var activityStatusStore: ActivityStatusStore?
    private let journalClient: (any JournalServing)?
    private let wellnessClient: (any WellnessServing)?

    init(
        client: any TodayServing = FixtureTodayClient(),
        tokenProvider: (() async throws -> String)? = nil,
        modelContext: ModelContext? = nil,
        activityStatusClient: (any ActivityStatusServing)? = nil,
        journalClient: (any JournalServing)? = nil,
        wellnessClient: (any WellnessServing)? = nil
    ) {
        self.tokenProvider = tokenProvider
        self.journalClient = tokenProvider == nil ? nil : journalClient
        self.wellnessClient = tokenProvider == nil ? nil : wellnessClient
        _store = State(
            initialValue: TodayStore(
                client: client,
                tokenProvider: tokenProvider,
                modelContext: modelContext
            )
        )
        _activityStatusStore = State(
            initialValue: activityStatusClient.flatMap { client in
                tokenProvider.map { ActivityStatusStore(client: client, tokenProvider: $0) }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch store.phase {
                case .loading:
                    SharpitLoadingInstrument()
                case .loaded(let fold):
                    TodayFoldView(
                        fold: fold,
                        pulseScores: store.pulseScores,
                        sessionDoneCelebrations: store.sessionDoneCelebrations,
                        tokenProvider: tokenProvider,
                        onArrival: { store.handleArrivalWins(fold: fold) },
                        onSessionLinked: { Task { await store.refresh() } }
                    )
                case .empty(let empty):
                    TodayEmptyView(empty: empty)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Résumé indisponible", systemImage: "wifi.slash")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Réessayer") {
                            Task { await store.load(resetToLoading: true) }
                        }
                    }
                case .unauthorized:
                    ContentUnavailableView {
                        Label("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
                    } description: {
                        Text("Reconnecte-toi pour recharger le résumé.")
                    }
                }
            }
            .background(SharpitCanvasBackground())
            .navigationTitle(store.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LiquidNavChrome())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let activityStatusStore {
                        ActivityStatusButton(store: activityStatusStore)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let journalClient, let wellnessClient, let tokenProvider {
                        NavigationLink {
                            JournalView(
                                client: journalClient,
                                wellness: wellnessClient,
                                tokenProvider: tokenProvider
                            )
                        } label: {
                            Label("Journal", systemImage: "book.closed")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    WeatherToolbarChip(service: weather)
                }
            }
            .refreshable {
                await store.refresh()
                weather.start()
            }
            .task {
                await store.load(resetToLoading: true)
                weather.start()
            }
        }
    }
}

private struct TodayFoldView: View {
    @Environment(ShellRouter.self) private var router

    let fold: TodayFold
    var pulseScores: Bool = false
    var sessionDoneCelebrations: Set<String> = []
    var tokenProvider: (() async throws -> String)?
    var onArrival: () -> Void = {}
    /// Called once a prescription has been linked, so Today reloads and shows it as done.
    var onSessionLinked: () -> Void = {}

    @State private var selectedPreview: PlannedSessionPreview?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                InkVerdictPlate(plate: fold.plate, revealed: true)
                evidenceSection
                if !fold.gauges.isEmpty {
                    OvernightGaugePair(gauges: fold.gauges, pulseScores: pulseScores)
                }
                if let consistency = fold.consistency, !consistency.days.isEmpty {
                    ConsistencyStrip(consistency: consistency) {
                        router.select(.plan)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .modifier(ScrollUnderGlass())
        .sheet(item: $selectedPreview) { preview in
            PlannedSessionDrawer(preview: preview, linking: linkContext) { context in
                router.discussWithCoach(about: context)
            }
        }
        .task { onArrival() }
    }

    /// Nil without a token: a fixture-backed Today has nothing to link against.
    private var linkContext: SessionLinkContext? {
        guard let tokenProvider else { return nil }
        return SessionLinkContext(
            referenceDate: TrainingDayId.date(fold.trainingDayId) ?? .now,
            activities: ActivityClient(),
            linker: PlannedSessionClient(),
            tokenProvider: tokenProvider,
            onLinked: onSessionLinked
        )
    }

    @ViewBuilder
    private var evidenceSection: some View {
        if fold.sessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SharpitEyebrow("Séance")
                RestDayPlate()
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                SharpitEyebrow("Séance")
                ForEach(fold.sessions) { session in
                    TodaySessionLink(
                        session: session,
                        showPriorityTag: SessionPriorityPolicy.showsTag(
                            sessionCount: fold.sessions.count,
                            priority: session.priority
                        ),
                        celebrateDone: sessionDoneCelebrations.contains(session.id),
                        tokenProvider: tokenProvider,
                        onOpenPreview: { selectedPreview = $0 }
                    )
                }
            }
        }
    }
}


/// Today's session line, made openable.
///
/// The same rule as the plan, because it is the same object seen from another screen: a
/// session that was done opens its own record, a prescription opens the drawer. Today
/// carries no activity payload, so the detail screen loads it from the id.
private struct TodaySessionLink: View {
    let session: SessionCardModel
    let showPriorityTag: Bool
    let celebrateDone: Bool
    let tokenProvider: (() async throws -> String)?
    let onOpenPreview: (PlannedSessionPreview) -> Void

    private var plate: some View {
        SessionPlate(
            session: session,
            showPriorityTag: showPriorityTag,
            celebrateDone: celebrateDone
        )
    }

    var body: some View {
        switch session.kind {
        case .done:
            // Only when the screen can actually fetch it. A fixture-backed Today has no
            // token, and a link that dead-ends is worse than a plate that does not move.
            if let tokenProvider {
                NavigationLink {
                    ActivityDetailView(
                        activity: session.id,
                        initialActivity: nil,
                        client: ActivityClient(),
                        tokenProvider: tokenProvider
                    )
                } label: {
                    plate
                }
                .buttonStyle(.plain)
            } else {
                plate
            }
        case .planned:
            Button {
                onOpenPreview(PlannedSessionPreview(card: session))
            } label: {
                plate
            }
            .buttonStyle(.plain)
        }
    }
}

private struct TodayEmptyView: View {
    let empty: V1TodayEmpty

    var body: some View {
        ContentUnavailableView {
            Label(empty.title, systemImage: "tray")
        } description: {
            if let message = empty.message {
                Text(message)
            }
        } actions: {
            if let url = URL(string: empty.webURL) {
                Link("Continuer sur le web", destination: url)
            }
        }
    }
}

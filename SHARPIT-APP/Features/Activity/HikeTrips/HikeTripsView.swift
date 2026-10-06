import SwiftUI

/// Activité › Séjours: realised hikes of several days gathered under one name — the web's
/// `/activite/sejours`. Each opens its page (`HikeTripDetailView`); « + » gathers hikes into a new one.
struct HikeTripsView: View {
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String

    @State private var store: HikeTripStore
    @State private var isCreating = false
    @State private var openedTripId: String?

    init(
        activityClient: any ActivityServing,
        tokenProvider: @escaping () async throws -> String,
        client: any HikeTripServing = HikeTripClient()
    ) {
        self.activityClient = activityClient
        self.tokenProvider = tokenProvider
        _store = State(initialValue: HikeTripStore(client: client, activities: activityClient, tokenProvider: tokenProvider))
    }

    var body: some View {
        Group {
            switch store.phase {
            case .unauthorized:
                SharpitStateMessage.sessionExpired()
            case .failed(let message):
                SharpitStateMessage.failed(message) { Task { await store.load() } }
            case .loading, .loaded:
                list
            }
        }
        .navigationTitle("Séjours")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Créer un séjour", systemImage: "plus") { isCreating = true }
            }
        }
        .sheet(isPresented: $isCreating) {
            HikeTripPickerSheet(store: store, mode: .create(seedId: nil)) { trip in
                openedTripId = trip.id
            }
        }
        .navigationDestination(item: $openedTripId) { id in
            HikeTripDetailView(store: store, tripId: id, activityClient: activityClient, tokenProvider: tokenProvider)
        }
        .task { await store.load() }
    }

    private var list: some View {
        List {
            if store.phase == .loaded, store.trips.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Aucun séjour", systemImage: "figure.hiking")
                    } description: {
                        Text("Regroupe plusieurs randonnées en un séjour : ses étapes et ses totaux, d'un coup d'œil.")
                    } actions: {
                        Button("Créer un séjour") { isCreating = true }
                            .buttonStyle(.bordered)
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                Section(
                    eyebrow: "Séjours",
                    footer: "Randonnées de plusieurs jours regroupées — étapes et totaux par séjour."
                ) {
                    if store.phase == .loading {
                        ForEach(0..<3, id: \.self) { _ in
                            HikeTripRow(name: "Séjour en montagne", meta: ["3 – 5 oct. 2026", "3 étapes", "42,0 km"])
                        }
                        .redacted(reason: .placeholder)
                    } else {
                        ForEach(store.trips) { trip in
                            NavigationLink {
                                HikeTripDetailView(
                                    store: store,
                                    tripId: trip.id,
                                    activityClient: activityClient,
                                    tokenProvider: tokenProvider
                                )
                            } label: {
                                HikeTripRow(name: trip.name, meta: HikeTripReadout.listMeta(trip.summary))
                            }
                        }
                    }
                }
                .sharpitListRows()
            }
        }
        .sharpitGroupedList()
        .refreshable { await store.load() }
    }
}

/// A séjour in a list: its name, then its days, stages and distance.
private struct HikeTripRow: View {
    let name: String
    let meta: [String]

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                Text(meta.joined(separator: " · "))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(1)
            }
        } icon: {
            SharpitRowIcon(symbol: "figure.hiking", tone: SharpitSportTone.label(for: .hike))
        }
    }
}

/// Activité's way in to the séjours, under the page's title — shown once the history holds a hike.
struct HikeTripsEntry: View {
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String

    var body: some View {
        NavigationLink {
            HikeTripsView(activityClient: activityClient, tokenProvider: tokenProvider)
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                SharpitRowIcon(symbol: "figure.hiking", tone: SharpitSportTone.label(for: .hike))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Séjours")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("Tes randonnées de plusieurs jours, étape par étape")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, SharpitSpacing.cardPadding)
            .padding(.vertical, SharpitSpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous)
                    .fill(SharpitColor.analysisSurface)
            )
            .contentShape(RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius, style: .continuous))
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityHint("Ouvre tes séjours de randonnée")
    }
}

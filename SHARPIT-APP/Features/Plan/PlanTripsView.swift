import SwiftUI

/// Plan → « … » → Déplacements: the dated periods that change what can be planned, those under
/// way first. The server drops them once over, so nothing here is ever in the past.
struct PlanTripsView: View {
    @State private var store: CoachMemoryStore
    @State private var route: CoachMemoryFormRoute?
    @State private var hasLoaded = false

    private static let kinds: [CoachMemoryType] = [.travel, .constraint]

    init(client: any CoachMemoryServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: CoachMemoryStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        content
            .navigationTitle("Déplacements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { route = .new } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Ajouter un déplacement ou une contrainte")
                }
            }
            .navigationDestination(item: $route) { route in
                CoachMemoryEntryForm(store: store, kinds: Self.kinds, entry: route.entry)
            }
            .task {
                await store.load()
                hasLoaded = true
            }
    }

    @ViewBuilder private var content: some View {
        let schedule = PlanTravel.schedule(store.entries)
        if !schedule.isEmpty {
            List {
                section(String(localized: "En cours"), schedule.current)
                section(String(localized: "À venir"), schedule.upcoming)
            }
            .sharpitGroupedList()
            .refreshable { await store.load() }
        } else if !hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SharpitCanvasBackground())
        } else if let failure = store.errorMessage {
            SharpitStateMessage.failed(failure) {
                Task { await store.load() }
            }
        } else {
            emptyState
        }
    }

    private var emptyState: some View {
        VStack(spacing: SharpitSpacing.md) {
            SharpitIconTile(symbol: CoachMemoryType.travel.symbol, size: 56)
            Text("Aucun déplacement prévu")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            SharpitPrimaryButton(title: String(localized: "Ajouter un déplacement")) { route = .new }
                .frame(maxWidth: 260)
        }
        .padding(SharpitSpacing.pageInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharpitCanvasBackground())
    }

    @ViewBuilder private func section(_ eyebrow: String, _ entries: [CoachMemoryEntry]) -> some View {
        if !entries.isEmpty {
            Section(eyebrow: eyebrow) {
                ForEach(entries) { entry in
                    Button { route = .edit(entry) } label: {
                        CoachMemoryEntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        SharpitSwipeDeleteButton {
                            Task { await store.deleteEntry(id: entry.id) }
                        }
                    }
                }
            }
            .sharpitListRows()
        }
    }
}

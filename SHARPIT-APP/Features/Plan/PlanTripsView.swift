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
            .navigationBarTitleDisplayMode(.large)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button { route = .new } label: { Text("Déclarer un déplacement").frame(maxWidth: .infinity) }
                    .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                    .padding(.horizontal, 16)
                    .padding(.vertical, SharpitSpacing.xs)
                    .background(SharpitColor.card)
            }
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
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: CoachMemoryType.travel.symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(SharpitColor.slate)
                .accessibilityHidden(true)
            Text("Aucun déplacement prévu")
                .font(SharpitTypography.system(size: 20, weight: .semibold, relativeTo: .title3))
                .foregroundStyle(SharpitColor.foreground)
            Text("Dis où tu pars et quand : le plan s'allège ou se déplace sur ces jours-là.")
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
            Button("Déclarer un déplacement") { route = .new }
                .buttonStyle(CliniqueButtonStyle(kind: .primary))
                .padding(.top, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, SharpitSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SharpitColor.card)
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

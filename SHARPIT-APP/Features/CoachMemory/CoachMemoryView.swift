import SwiftUI

/// Coach → Mémoire: what lasts about the athlete, in their words and as injuries, preferences
/// and notes. Dated trips and constraints shape the calendar, so they live in Plan
/// (`PlanTripsView`).
struct CoachMemoryView: View {
    @State private var store: CoachMemoryStore
    @State private var route: CoachMemoryFormRoute?

    private static let kinds: [CoachMemoryType] = [.injury, .preference, .note]

    init(client: any CoachMemoryServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: CoachMemoryStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        List {
            contextSection
            entriesSection(String(localized: "Blessures"), types: [.injury])
            entriesSection(String(localized: "Préférences & notes"), types: [.preference, .note])
        }
        .sharpitGroupedList()
        .navigationTitle("Mémoire du coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { route = .new } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ajouter une blessure, une préférence ou une note")
            }
        }
        .navigationDestination(item: $route) { route in
            CoachMemoryEntryForm(store: store, kinds: Self.kinds, entry: route.entry)
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    private var contextSection: some View {
        Section(eyebrow: String(localized: "Ce que le coach sait de toi")) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                TextEditor(text: $store.profileContextText)
                    .frame(minHeight: 120)
                    .font(SharpitTypography.body)
                    .scrollContentBackground(.hidden)

                HStack {
                    Text("\(store.profileContextText.count) / 4 000")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .monospacedDigit()
                    Spacer()
                    if store.isContextDirty {
                        Button("Enregistrer") {
                            Task { await store.saveContext() }
                        }
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.primary)
                    }
                }
            }
            .padding(.vertical, SharpitSpacing.xxs)
        }
        .sharpitListRows()
    }

    /// A kind with nothing in it takes no room: the « + » is how it starts.
    @ViewBuilder private func entriesSection(_ eyebrow: String, types: Set<CoachMemoryType>) -> some View {
        let entries = store.entries.filter { types.contains($0.type) }
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

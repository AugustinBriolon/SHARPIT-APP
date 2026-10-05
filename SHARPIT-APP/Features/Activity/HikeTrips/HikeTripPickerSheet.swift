import SwiftUI

/// Picks hikes not yet in a séjour: to make a new one (a name, at least two hikes — the web's
/// `CreateHikeTripDialog`, seeded by the hike it was opened from) or to add stages to one
/// (`HikeTripAddStepControl`). Both wait for the server, which may refuse a hike already taken.
struct HikeTripPickerSheet: View {
    enum Mode: Equatable {
        /// A new séjour; `seedId` is the hike it was opened from, already picked and kept.
        case create(seedId: String?)
        case add(tripId: String)
    }

    let store: HikeTripStore
    let mode: Mode
    var onCreated: (V1HikeTrip) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<String>

    init(store: HikeTripStore, mode: Mode, onCreated: @escaping (V1HikeTrip) -> Void = { _ in }) {
        self.store = store
        self.mode = mode
        self.onCreated = onCreated
        if case .create(let seedId?) = mode {
            _selected = State(initialValue: [seedId])
        } else {
            _selected = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if isCreating {
                    Section(eyebrow: "Nom") {
                        TextField("Ex. Queyras · août", text: $name)
                            .font(SharpitTypography.body)
                            .submitLabel(.done)
                    }
                    .sharpitListRows()
                }

                Section(eyebrow: "Randonnées", footer: footer) {
                    if store.phase == .loading, store.hikes.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if candidates.isEmpty {
                        Text("Aucune randonnée disponible : celles déjà dans un séjour n'apparaissent pas ici.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    } else {
                        ForEach(candidates) { hike in
                            hikeRow(hike)
                        }
                    }
                }
                .sharpitListRows()

                if let saveError = store.saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalRisk)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .sharpitGroupedList()
            .navigationTitle(isCreating ? "Créer un séjour" : "Ajouter une étape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if store.isSaving {
                        ProgressView()
                    } else {
                        Button(isCreating ? "Créer" : "Ajouter") { Task { await confirm() } }
                            .disabled(!canConfirm)
                    }
                }
            }
        }
        .sharpitSheet()
        .interactiveDismissDisabled(store.isSaving)
        .onAppear { store.saveError = nil }
        .task {
            if store.phase != .loaded { await store.load() }
        }
    }

    private var isCreating: Bool {
        if case .create = mode { return true }
        return false
    }

    private var seedId: String? {
        if case .create(let seedId) = mode { return seedId }
        return nil
    }

    /// Hikes free to join, newest first; the seed stays listed even once the list is reread.
    private var candidates: [V1ActivityListItem] {
        store.availableHikes
    }

    private var canConfirm: Bool {
        if isCreating {
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selected.count >= 2
        }
        return !selected.isEmpty
    }

    private var footer: String {
        isCreating
            ? HikeTripReadout.selectionFooter(selected: selected.count)
            : "Seules les randonnées hors séjour sont proposées."
    }

    private func hikeRow(_ hike: V1ActivityListItem) -> some View {
        let isPicked = selected.contains(hike.id)
        let member = V1HikeTripMember(
            id: hike.id,
            date: hike.date,
            title: hike.title,
            duration: hike.duration,
            distanceM: hike.distanceM,
            elevationM: hike.elevationM
        )
        return Button {
            guard hike.id != seedId else { return }
            SharpitMotion.run(SharpitMotion.selection) {
                if isPicked { selected.remove(hike.id) } else { selected.insert(hike.id) }
            }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayTitle)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1)
                    Text(HikeTripReadout.memberMeta(member).joined(separator: " · "))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(1)
                }
                Spacer(minLength: SharpitSpacing.xs)
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isPicked ? SharpitColor.primary : SharpitColor.mutedForeground)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func confirm() async {
        let ids = candidates.map(\.id).filter { selected.contains($0) }
        switch mode {
        case .create:
            if let trip = await store.create(name: name, activityIds: ids) {
                dismiss()
                onCreated(trip)
            }
        case .add(let tripId):
            if await store.addSteps(ids, to: tripId) {
                dismiss()
            }
        }
    }
}

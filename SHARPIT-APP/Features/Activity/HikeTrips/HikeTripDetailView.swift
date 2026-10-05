import SwiftUI

/// One séjour — the web's `/activite/sejours/[id]`: its days and totals, the places walked
/// through, then the stages in order, each opening its activity. « … » renames it, adds a stage
/// or deletes it (its hikes stay in the history); a stage swiped away leaves the séjour only.
struct HikeTripDetailView: View {
    let store: HikeTripStore
    let tripId: String
    let activityClient: any ActivityServing
    let tokenProvider: () async throws -> String

    @Environment(\.dismiss) private var dismiss
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var isConfirmingDeletion = false
    @State private var isAddingSteps = false

    var body: some View {
        Group {
            if let trip = store.trip(id: tripId) {
                content(trip)
            } else if store.phase == .loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                SharpitStateMessage(
                    title: "Séjour introuvable",
                    symbol: "figure.hiking",
                    detail: "Il a peut-être été supprimé depuis un autre appareil."
                )
            }
        }
        .background(SharpitCanvasBackground())
        .navigationTitle(store.trip(id: tripId)?.name ?? "Séjour")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let trip = store.trip(id: tripId) {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Renommer", systemImage: "pencil") {
                            draftName = trip.name
                            isRenaming = true
                        }
                        Button("Ajouter une étape", systemImage: "plus") { isAddingSteps = true }
                        Divider()
                        Button("Supprimer", systemImage: "trash", role: .destructive) {
                            isConfirmingDeletion = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Actions du séjour")
                }
            }
        }
        .alert("Renommer le séjour", isPresented: $isRenaming) {
            TextField("Ex. Queyras · août", text: $draftName)
            Button("Annuler", role: .cancel) {}
            Button("Enregistrer") { store.rename(tripId, to: draftName) }
        }
        .confirmationDialog("Supprimer ce séjour ?", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("Supprimer le séjour", role: .destructive) {
                store.delete(tripId)
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les randonnées liées sont conservées dans ton historique et détachées du séjour.")
        }
        .sheet(isPresented: $isAddingSteps) {
            HikeTripPickerSheet(store: store, mode: .add(tripId: tripId))
        }
        .task {
            if store.trip(id: tripId) == nil { await store.load() }
        }
    }

    private func content(_ trip: V1HikeTrip) -> some View {
        let summary = trip.summary
        return List {
            Section {
                HStack(spacing: SharpitSpacing.sm) {
                    SharpitStatTile(
                        caption: "Distance",
                        value: summary.distanceM.map { SharpitFigureFormat.kilometers($0 / 1_000) } ?? "—",
                        unit: summary.distanceM == nil ? nil : "km"
                    )
                    SharpitStatTile(
                        caption: "Dénivelé +",
                        value: summary.elevationM.map { "\(Int($0.rounded()))" } ?? "—",
                        unit: summary.elevationM == nil ? nil : "m"
                    )
                    SharpitStatTile(
                        caption: "Durée",
                        value: summary.durationSec.map { SharpitFigureFormat.duration(minutes: $0 / 60) } ?? "—"
                    )
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text(HikeTripReadout.listMeta(summary).prefix(2).joined(separator: " · "))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .textCase(nil)
            }

            if let waypoints = HikeTripReadout.waypoints(summary.locationLabels) {
                Section(eyebrow: "Points de passage") {
                    Text(waypoints)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .sharpitListRows()
            }

            Section(eyebrow: "Étapes", footer: stepsFooter(trip)) {
                ForEach(Array(trip.activities.enumerated()), id: \.element.id) { index, member in
                    NavigationLink {
                        ActivityDetailView(activity: member.id, client: activityClient, tokenProvider: tokenProvider)
                    } label: {
                        HikeTripStepRow(index: index, member: member)
                    }
                    .swipeActions(edge: .trailing) {
                        if trip.activities.count > 1 {
                            Button("Retirer", systemImage: "minus.circle") {
                                store.removeStep(member.id, from: tripId)
                            }
                        }
                    }
                }
                Button {
                    isAddingSteps = true
                } label: {
                    Label {
                        Text("Ajouter une étape")
                            .font(SharpitTypography.bodyEmphasis)
                    } icon: {
                        SharpitRowIcon(symbol: "plus")
                    }
                }
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .refreshable { await store.load() }
    }

    private func stepsFooter(_ trip: V1HikeTrip) -> String {
        trip.activities.count > 1
            ? "Balaie une étape vers la gauche pour la retirer du séjour ; la randonnée reste dans ton historique."
            : "Un séjour garde au moins une étape. Pour la libérer, supprime le séjour."
    }
}

/// A stage: its rank in the walk, its name, then its day and measures.
private struct HikeTripStepRow: View {
    let index: Int
    let member: V1HikeTripMember

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Text("\(index + 1)")
                .font(SharpitTypography.label)
                .foregroundStyle(SharpitColor.primary)
                .frame(width: 24, height: 24)
                .background(SharpitColor.primary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayTitle)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                Text(HikeTripReadout.memberMeta(member).joined(separator: " · "))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Étape \(index + 1), \(member.displayTitle), \(HikeTripReadout.memberMeta(member).joined(separator: ", "))")
    }
}

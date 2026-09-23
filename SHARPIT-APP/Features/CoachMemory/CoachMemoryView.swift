import SwiftUI

/// Réglages → Mémoire du coach: permanent athlete context and dated constraints/travels.
struct CoachMemoryView: View {
    @State private var store: CoachMemoryStore
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var showsCreateSheet = false
    @State private var selectedEntryForDetail: CoachMemoryEntry?

    init(client: any CoachMemoryServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: CoachMemoryStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        List {
            contextSection
            datedEntriesSection
        }
        .sharpitGroupedList()
        .navigationTitle("Mémoire du coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showsCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ajouter un déplacement ou une contrainte")
            }
        }
        .sheet(isPresented: $showsCreateSheet, onDismiss: {
            Task { await store.load() }
        }) {
            TravelMemorySheet(store: store)
        }
        .sheet(item: $selectedEntryForDetail) { entry in
            CoachMemoryDetailDrawer(entry: entry) {
                await store.deleteEntry(id: entry.id)
            }
        }
        .task {
            await store.load()
        }
        .refreshable {
            await store.load()
        }
    }

    private var contextSection: some View {
        Section(
            eyebrow: "Contexte permanent",
            footer: "Informations durables que le coach IA prend en compte pour adapter chaque analyse et recommandation."
        ) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                TextEditor(text: $store.profileContextText)
                    .frame(minHeight: 90)
                    .font(SharpitTypography.body)

                HStack {
                    Text("\(store.profileContextText.count) / 4 000")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .monospacedDigit()

                    Spacer()

                    if store.isSavingContext {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if store.isContextDirty {
                        Button("Enregistrer") {
                            Task {
                                let ok = await store.saveContext()
                                if ok {
                                    toastCenter?.show("Contexte enregistré", symbol: "checkmark.circle.fill", tone: .success)
                                } else {
                                    toastCenter?.show("Erreur d'enregistrement", symbol: "exclamationmark.triangle.fill", tone: .error)
                                }
                            }
                        }
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.primary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .sharpitListRows()
    }

    private var datedEntriesSection: some View {
        Section(
            eyebrow: "Déplacements & contraintes",
            footer: "Périodes temporaires avec impact direct sur les séances planifiées."
        ) {
            if store.entries.isEmpty && !store.isLoading {
                Text("Aucun déplacement ou contrainte planifié.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(.vertical, 4)
            } else {
                ForEach(store.entries) { entry in
                    Button {
                        selectedEntryForDetail = entry
                    } label: {
                        entryRow(entry)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await store.deleteEntry(id: entry.id) }
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .sharpitListRows()
    }

    private func entryRow(_ entry: CoachMemoryEntry) -> some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Image(systemName: entry.type == .travel ? "airplane" : "clock.badge.exclamationmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SharpitColor.primary)
                .frame(width: 28, height: 28)
                .background(SharpitColor.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)

                Text(entry.formattedDateRange)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)

                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: SharpitSpacing.xs)

            constraintBadge(entry.trainingConstraint)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SharpitColor.mutedForeground.opacity(0.4))
        }
        .padding(.vertical, 4)
    }

    private func constraintBadge(_ constraint: TravelTrainingConstraint) -> some View {
        Text(constraint.badgeText)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(constraintColor(constraint))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(constraintColor(constraint).opacity(0.12), in: Capsule())
    }

    private func constraintColor(_ constraint: TravelTrainingConstraint) -> Color {
        switch constraint {
        case .full: SharpitColor.primary
        case .reduced: SharpitColor.signalCaution
        case .mobilityOnly: SharpitColor.signalCaution
        case .none: SharpitColor.signalRisk
        }
    }
}

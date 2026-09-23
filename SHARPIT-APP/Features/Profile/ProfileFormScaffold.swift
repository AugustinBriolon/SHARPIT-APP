import SwiftUI

/// The frame Profil and Seuils share: the profile's loading states, the fields, and one
/// save that refuses an entry that does not read.
///
/// Both screens edit the same profile through the same store and differ only in which fields
/// they show, so the frame is written once — the phases, the error line and the save are not
/// two screens' worth of decisions. Save sits in the navigation bar, where the system puts the
/// commit of a pushed form; a field's own error names what is wrong beneath it, so the button
/// needs no sentence explaining why it is off.
struct ProfileFormScaffold<Fields: View>: View {
    let title: String
    let subtitle: String
    @Bindable var store: AthleteProfileStore
    @Binding var form: ProfileFormState
    /// The fields this screen owns, so a save only validates what is on screen.
    let ownedFields: [ProfileFormField]
    @ViewBuilder let fields: Fields

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch store.phase {
            case .unauthorized:
                SharpitStateMessage.sessionExpired()
            case .failed(let message):
                SharpitStateMessage.failed(message) { Task { await load(force: true) } }
            case .idle, .loading, .loaded:
                list
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { saveButton }
        .task { await load() }
    }

    private var list: some View {
        List {
            SharpitListIntro(subtitle)
            if store.phase == .loaded {
                Group { fields }.sharpitListRows()
                saveErrorSection
            } else {
                ProfileFormSkeleton()
            }
        }
        .sharpitGroupedList()
        .scrollDismissesKeyboard(.interactively)
    }

    @ToolbarContentBuilder
    private var saveButton: some ToolbarContent {
        if store.phase == .loaded {
            ToolbarItem(placement: .confirmationAction) {
                if store.isSaving {
                    ProgressView()
                } else {
                    Button("Enregistrer") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private var saveErrorSection: some View {
        if let saveError = store.saveError {
            Section {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
            }
            .listRowBackground(Color.clear)
        }
    }

    /// Nothing typed wrong, and something to send.
    private var canSave: Bool {
        ownedFields.allSatisfy { form.error(for: $0) == nil }
            && !form.patch(against: store.profile).isEmpty
    }

    private func load(force: Bool = false) async {
        if force || store.phase != .loaded {
            await store.load()
        }
        if store.phase == .loaded {
            form = ProfileFormState(profile: store.profile)
        }
    }

    private func save() async {
        guard await store.save(form.patch(against: store.profile)) else { return }
        form = ProfileFormState(profile: store.profile)
        dismiss()
    }
}

/// Two field groups shaped like real ones, redacted, so Profil and Seuils never open on a
/// bare spinner (`docs/adr/0008`) — the exact fields differ per screen, but a labelled row
/// is a labelled row.
private struct ProfileFormSkeleton: View {
    @ViewBuilder
    var body: some View {
        group(rows: 2)
        group(rows: 2)
    }

    private func group(rows: Int) -> some View {
        Section {
            ForEach(0..<rows, id: \.self) { _ in row }
        }
        .sharpitListRows()
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    private var row: some View {
        HStack {
            Text("Label")
                .font(SharpitTypography.body)
            Spacer()
            Text("000")
                .font(SharpitTypography.body)
        }
        .foregroundStyle(SharpitColor.mutedForeground)
    }
}

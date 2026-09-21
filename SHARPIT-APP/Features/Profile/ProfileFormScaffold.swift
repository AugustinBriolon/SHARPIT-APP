import SwiftUI

/// The frame Profil and Seuils share: the profile's loading states, the fields, and one
/// save button that refuses an entry that does not read.
///
/// Both screens edit the same profile through the same store and differ only in which fields
/// they show, so the frame is written once — the phases, the error line and the save are not
/// two screens' worth of decisions.
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
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                Text(subtitle)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .padding(SharpitSpacing.pageInset)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            ProgressView("Lecture du profil…")
                .frame(maxWidth: .infinity)
        case .unauthorized:
            Label("Session expirée. Reconnecte-toi.", systemImage: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(SharpitColor.signalCaution)
        case .failed(let message):
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(SharpitColor.signalCaution)
                Button("Réessayer") { Task { await load(force: true) } }
                    .font(SharpitTypography.bodyEmphasis)
            }
        case .loaded:
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                fields
                saveBar
            }
        }
    }

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            if let saveError = store.saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
            }
            Button {
                Task { await save() }
            } label: {
                HStack(spacing: SharpitSpacing.xs) {
                    if store.isSaving { ProgressView().controlSize(.small) }
                    Text(store.isSaving ? "Enregistrement…" : "Enregistrer")
                        .font(SharpitTypography.bodyEmphasis)
                }
                .frame(maxWidth: .infinity)
                .padding(SharpitSpacing.sm)
                .sharpitSurface(.ink)
            }
            .buttonStyle(.sharpitPressable)
            .disabled(store.isSaving || !canSave)
            Text(saveHint)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Nothing typed wrong, and something to send.
    private var canSave: Bool {
        firstOwnedError == nil && !form.patch(against: store.profile).isEmpty
    }

    private var firstOwnedError: String? {
        ownedFields.compactMap { form.error(for: $0) }.first
    }

    private var saveHint: String {
        if let firstOwnedError { return firstOwnedError }
        if form.patch(against: store.profile).isEmpty { return "Rien à enregistrer." }
        return "Seuls les champs modifiés sont envoyés."
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

import SwiftUI

/// Chooses what the journal asks for each day.
struct JournalPrefsDrawer: View {
    @Bindable var store: JournalStore
    @Environment(\.dismiss) private var dismiss

    @State private var filter: JournalCategory?
    @State private var newCustomLabel = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    quotaLine
                    filterChips

                    ForEach(categories) { category in
                        JournalPrefsSection(title: category.label) {
                            ForEach(JournalCatalogue.inCategory(category)) { trackable in
                                JournalPrefsToggleRow(
                                    label: trackable.label,
                                    symbolName: trackable.symbolName,
                                    isOn: store.prefs.isEnabled(trackable.id),
                                    isBlocked: isBlocked(enabled: store.prefs.isEnabled(trackable.id))
                                ) { enabled in
                                    Task { await store.setTrackableEnabled(trackable.id, enabled) }
                                }
                            }
                        }
                    }

                    if filter == nil || filter == .bienEtre {
                        customSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.pageInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SharpitCanvasBackground())
            .navigationTitle("Personnaliser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var categories: [JournalCategory] {
        filter.map { [$0] } ?? JournalCategory.allCases
    }

    @ViewBuilder
    private var quotaLine: some View {
        if let failure = store.saveFailure {
            Text(failure)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.signalCaution)
        }
        if !store.isPro {
            // The count covers items the app does not list — the web's automatic and
            // diet trackables — so it matches what the athlete sees on the web.
            Text("\(store.prefs.enabledCount) / \(JournalPrefs.freeEnabledLimit) suivis actifs")
                .font(SharpitTypography.meta)
                .foregroundStyle(
                    store.prefs.canEnableAnother(isPro: false)
                        ? SharpitColor.mutedForeground
                        : SharpitColor.signalCaution
                )
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: SharpitSpacing.xxs) {
                JournalFilterChip(label: "Tous", isSelected: filter == nil) { filter = nil }
                ForEach(JournalCategory.allCases) { category in
                    JournalFilterChip(label: category.label, isSelected: filter == category) {
                        filter = category
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }

    private var customSection: some View {
        JournalPrefsSection(title: "Personnalisé") {
            if store.isPro {
                HStack(spacing: SharpitSpacing.xs) {
                    TextField("Ajouter un suivi", text: $newCustomLabel)
                        .textFieldStyle(.plain)
                        .font(SharpitTypography.body)
                        .submitLabel(.done)
                        .onSubmit { addCustom() }
                    Button("Ajouter", action: addCustom)
                        .font(SharpitTypography.meta)
                        .disabled(newCustomLabel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(SharpitSpacing.cardPadding)
                .sharpitSurface(.panel)
            } else {
                Text("Les suivis personnalisés demandent un compte Pro.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .padding(SharpitSpacing.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sharpitSurface(.panel)
            }

            ForEach(store.prefs.customItems) { item in
                JournalPrefsToggleRow(
                    label: item.label,
                    symbolName: JournalCatalogue.customSymbolName,
                    isOn: item.enabled,
                    isBlocked: isBlocked(enabled: item.enabled)
                ) { enabled in
                    Task { await store.setCustomItemEnabled(item.id, enabled) }
                }
                .swipeActions {
                    Button("Supprimer", role: .destructive) {
                        Task { await store.removeCustomItem(item.id) }
                    }
                }
                .contextMenu {
                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                        Task { await store.removeCustomItem(item.id) }
                    }
                }
            }
        }
    }

    /// A free plan that has spent its quota can still turn things off, only not on.
    private func isBlocked(enabled: Bool) -> Bool {
        !enabled && !store.prefs.canEnableAnother(isPro: store.isPro)
    }

    private func addCustom() {
        let label = newCustomLabel
        newCustomLabel = ""
        Task { await store.addCustomItem(label: label) }
    }
}

private struct JournalPrefsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(title)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JournalFilterChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(SharpitTypography.meta)
                .foregroundStyle(isSelected ? SharpitColor.primary : SharpitColor.mutedForeground)
                .padding(.horizontal, SharpitSpacing.sm)
                .padding(.vertical, SharpitSpacing.xs)
                .sharpitSurface(isSelected ? .panelAlt : .chip)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct JournalPrefsToggleRow: View {
    let label: String
    let symbolName: String
    let isOn: Bool
    let isBlocked: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: symbolName)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(label)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .tint(SharpitColor.primary)
        .disabled(isBlocked)
        .opacity(isBlocked ? 0.5 : 1)
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

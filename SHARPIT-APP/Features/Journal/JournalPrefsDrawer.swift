import SwiftUI

/// Chooses what the journal asks for each day.
struct JournalPrefsDrawer: View {
    @Bindable var store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?

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
                                    hue: category.hue,
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
                .padding(.horizontal, 24)
                .padding(.vertical, SharpitSpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SharpitCanvasBackground())
            .navigationTitle("Mes signaux")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
        .onChange(of: store.saveFailure) { _, failure in
            if let failure {
                toastCenter?.show(
                    failure,
                    symbol: "exclamationmark.triangle.fill",
                    tone: .error,
                    autoDismissAfter: 3.5
                )
            }
        }
    }

    private var categories: [JournalCategory] {
        filter.map { [$0] } ?? JournalCategory.allCases
    }

    @ViewBuilder
    private var quotaLine: some View {
        if !store.isPro {
            // The count covers items the app does not list — the web's automatic and
            // diet trackables — so it matches what the athlete sees on the web.
            Text("\(store.prefs.enabledCount) / \(JournalPrefs.freeEnabledLimit) suivis actifs")
                .font(SharpitTypography.meta)
                .foregroundStyle(
                    store.prefs.canEnableAnother(isPro: false)
                        ? SharpitColor.slate
                        : SharpitColor.signalCaution
                )
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: SharpitSpacing.xs) {
                JournalFilterChip(label: String(localized: "Tous"), isSelected: filter == nil) { filter = nil }
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
        JournalPrefsSection(title: String(localized: "Personnalisé")) {
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
            } else {
                Text("Les suivis personnalisés demandent un compte Pro.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(store.prefs.customItems) { item in
                JournalPrefsToggleRow(
                    label: item.label,
                    symbolName: JournalCatalogue.customSymbolName,
                    hue: JournalCategory.bienEtre.hue,
                    isOn: item.enabled,
                    isBlocked: isBlocked(enabled: item.enabled)
                ) { enabled in
                    Task { await store.setCustomItemEnabled(item.id, enabled) }
                }
                .swipeActions {
                    SharpitSwipeDeleteButton {
                        Task { await store.removeCustomItem(item.id) }
                    }
                }
                .contextMenu {
                    SharpitDeleteMenuButton { Task { await store.removeCustomItem(item.id) } }
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
            SharpitEyebrow.title(title)
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
            // The app's chip: ink once chosen, a hairline otherwise.
            Text(label)
                .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(isSelected ? SharpitColor.primary : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? .clear : SharpitColor.outline, lineWidth: 1))
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct JournalPrefsToggleRow: View {
    let label: String
    let symbolName: String
    let hue: Color
    let isOn: Bool
    let isBlocked: Bool
    let onChange: @MainActor (Bool) -> Void

    @State private var toggleValue: Bool

    init(
        label: String,
        symbolName: String,
        hue: Color,
        isOn: Bool,
        isBlocked: Bool,
        onChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.label = label
        self.symbolName = symbolName
        self.hue = hue
        self.isOn = isOn
        self.isBlocked = isBlocked
        self.onChange = onChange
        _toggleValue = State(initialValue: isOn)
    }

    var body: some View {
        Toggle(isOn: $toggleValue) {
            HStack(spacing: SharpitSpacing.sm) {
                JournalRowIcon(symbolName: symbolName, hue: hue)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: isOn) { _, newValue in
            toggleValue = newValue
        }
        .onChange(of: toggleValue) { _, newValue in
            guard newValue != isOn else { return }
            onChange(newValue)
        }
    }
}

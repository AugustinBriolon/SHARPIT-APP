import SwiftUI

extension ActivityStatusId {
    /// Colour carries the mode's meaning, so it stays semantic: only `active` is a
    /// green light, and the two medical modes read as caution and risk.
    var tone: Color {
        switch self {
        case .active: SharpitColor.signalRecovery
        case .paused: SharpitColor.signalNeutral
        case .injured: SharpitColor.signalRisk
        case .sick: SharpitColor.signalCaution
        }
    }
}

/// The toolbar chip that opens the mode drawer, and the drawer itself.
struct ActivityStatusButton: View {
    @Bindable var store: ActivityStatusStore
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            // The toolbar slot is a fixed circle under Liquid Glass, which clips a
            // label: the mode travels as its own symbol and colour instead, and the
            // drawer names it.
            Image(systemName: store.store.status.symbolName)
                .foregroundStyle(store.store.status.tone)
        }
        .accessibilityLabel("Statut d'activité — \(store.store.status.label)")
        .accessibilityHint("Changer ton statut d'activité")
        .sheet(isPresented: $isPresented) {
            ActivityStatusDrawer(store: store)
        }
        .task { await store.load() }
    }
}

private struct ActivityStatusDrawer: View {
    @Bindable var store: ActivityStatusStore
    @Environment(\.dismiss) private var dismiss

    /// Mirrors the store while the sheet is open so the date picker can move before
    /// the athlete commits it.
    @State private var untilDate = ActivityStatusDate.defaultUntil()
    @State private var usesDeadline = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    if case .failed(let message) = store.phase {
                        Text(message)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalCaution)
                    }

                    SharpitEyebrow("Mode d'entraînement")
                    VStack(spacing: SharpitSpacing.xs) {
                        ForEach(ActivityStatusId.allCases, id: \.self) { status in
                            ActivityStatusOptionRow(
                                status: status,
                                isSelected: store.store.status == status
                            ) {
                                Task { await pick(status) }
                            }
                        }
                    }

                    if store.store.status != .active {
                        deadlineSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.pageInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SharpitCanvasBackground())
            .navigationTitle("Statut d'activité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: syncFromStore)
    }

    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Durée")
            Toggle("Jusqu'à une date", isOn: $usesDeadline)
                .font(SharpitTypography.bodyEmphasis)
                .tint(SharpitColor.primary)
                .onChange(of: usesDeadline) { _, isOn in
                    Task { await applyRetention(usesDeadline: isOn) }
                }

            if usesDeadline {
                DatePicker(
                    "Reprise prévue",
                    selection: $untilDate,
                    in: Date.now...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .font(SharpitTypography.body)
                .onChange(of: untilDate) { _, _ in
                    Task { await applyRetention(usesDeadline: true) }
                }
            } else {
                Text("Le mode reste actif jusqu'à ce que tu le changes.")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private func syncFromStore() {
        usesDeadline = store.store.retention.untilDate != nil
        if let day = store.store.retention.untilDate,
           let date = ActivityStatusDate.date(from: day) {
            untilDate = date
        }
    }

    private func pick(_ status: ActivityStatusId) async {
        guard status != store.store.status else { return }
        SharpitHaptics.play(.light)
        await store.apply(status: status, retention: retention(usesDeadline: usesDeadline))
        syncFromStore()
    }

    private func applyRetention(usesDeadline: Bool) async {
        guard store.store.status != .active else { return }
        await store.apply(
            status: store.store.status,
            retention: retention(usesDeadline: usesDeadline)
        )
    }

    private func retention(usesDeadline: Bool) -> ActivityStatusRetention {
        usesDeadline ? .untilDate(ActivityStatusDate.string(from: untilDate)) : .untilModified
    }
}

private struct ActivityStatusOptionRow: View {
    let status: ActivityStatusId
    let isSelected: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                Image(systemName: status.symbolName)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(status.tone)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.label)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    // The same line whether or not it is picked: a description that
                    // rewrites itself on selection reads as a different option.
                    Text(status.hint)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(isSelected ? .panelAlt : .panel)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

import SwiftUI

extension ActivityStatusId {
    /// Colour carries the mode's meaning, so it stays semantic: `active` is the normal
    /// state and reads in the text's colour; the others are alerts.
    var tone: Color {
        switch self {
        case .active: SharpitColor.foreground
        case .paused: SharpitColor.signalNeutral
        case .injured: SharpitColor.signalRisk
        case .sick: SharpitColor.signalCaution
        }
    }
}

extension ActivityStatusId {
    /// What the chip says: nothing for the normal state, which is not news; the mode and the day
    /// it ends otherwise.
    func chipTitle(untilDay: String?, calendar: Calendar = .current) -> String? {
        guard self != .active else { return nil }
        guard let untilDay, let date = ActivityStatusDate.date(from: untilDay, calendar: calendar) else { return label }
        return "\(label) · \(date.sharpitFormatted(.dateTime.day().month(.abbreviated)))"
    }
}

/// The toolbar chip that opens the mode drawer, and the drawer itself.
struct ActivityStatusButton: View {
    @Bindable var store: ActivityStatusStore
    /// In Résumé's chip row the mode is named; a toolbar slot is a fixed circle under Liquid
    /// Glass, which clips a label, so there the symbol and colour travel alone.
    var showsLabel = false
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            if showsLabel {
                HStack(spacing: SharpitSpacing.xs) {
                    Image(systemName: store.store.status.symbolName)
                        .foregroundStyle(store.store.status.tone)
                        .contentTransition(.symbolEffect(.replace))
                    if let title = store.store.status.chipTitle(untilDay: store.store.retention.untilDate) {
                        Text(title)
                            .foregroundStyle(SharpitColor.foreground)
                            .contentTransition(.opacity)
                    }
                }
                .sharpitGlassChip()
            } else {
                Image(systemName: store.store.status.symbolName)
                    .foregroundStyle(store.store.status.tone)
            }
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel("Statut d'activité — \(store.store.status.label)")
        .accessibilityHint("Changer ton statut d'activité")
        .sheet(isPresented: $isPresented) {
            ActivityStatusDrawer(store: store)
        }
        .task { await store.loadIfNeeded() }
    }
}

private struct ActivityStatusDrawer: View {
    @Bindable var store: ActivityStatusStore
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellRouter.self) private var router

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

                    SharpitEyebrow(String(localized: "Mode d'entraînement"))
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

                    impactSection
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
        .sharpitSheet()
        .presentationDragIndicator(.visible)
        .onAppear(perform: syncFromStore)
    }

    /// What the mode does to the plan and the coach, so a pick is never a blind one.
    private var impactSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(String(localized: "Ce que ça change"))
            Text(store.store.status.planningImpact)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
            if store.store.status != .active {
                CoachDiscussButton(title: String(localized: "En parler au coach")) {
                    router.discussWithCoach(about: CoachDiscuss.describe(.planning(horizonDays: 7)))
                    dismiss()
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }

    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(String(localized: "Durée"))
            Toggle("Jusqu'à une date", isOn: $usesDeadline)
                .font(SharpitTypography.bodyEmphasis)
                .tint(SharpitColor.primary)
                .onChange(of: usesDeadline) { _, isOn in
                    Task { await applyRetention(usesDeadline: isOn) }
                }

            if usesDeadline {
                DatePicker(
                    String(localized: "Reprise prévue"),
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

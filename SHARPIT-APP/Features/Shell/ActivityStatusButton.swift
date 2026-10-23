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
                    Text(store.store.status.label)
                        .foregroundStyle(SharpitColor.foreground)
                        .contentTransition(.opacity)
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

                    statusPlate
                    modesCard
                    if store.store.status != .active {
                        deadlineSection
                    }
                }
                .animation(SharpitMotion.reveal, value: store.store.status)
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

    /// The mode now, on the ink plate this tab leads with: what it is, what it changes for the
    /// plan and the coach, until when.
    private var statusPlate: some View {
        let status = store.store.status
        return VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                Image(systemName: status.symbolName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SharpitColor.highlightForeground)
                    .frame(width: 44, height: 44)
                    .background(SharpitColor.highlight, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    SharpitEyebrow(String(localized: "Mode actuel"))
                        .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.6))
                    Text(status.label)
                        .font(SharpitTypography.cardTitle)
                        .foregroundStyle(SharpitColor.inkSurfaceForeground)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                if let until = untilLabel {
                    SharpitPill(until, style: .lime)
                }
            }
            Text(status.planningImpact)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            if status != .active {
                Button {
                    router.discussWithCoach(about: CoachDiscuss.describe(.planning(horizonDays: 7)))
                    dismiss()
                } label: {
                    Label(String(localized: "En parler au coach"), systemImage: "arrow.up.right")
                        .labelStyle(.titleAndIcon)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.inkAccent)
                }
                .buttonStyle(.sharpitPressable)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.ink)
    }

    /// « 3 nov. » while a mode has an end, nothing when it holds until changed.
    private var untilLabel: String? {
        guard let day = store.store.retention.untilDate,
              let date = ActivityStatusDate.date(from: day) else { return nil }
        return String(localized: "Jusqu'au \(date.sharpitFormatted(.dateTime.day().month(.abbreviated)))")
    }

    private var modesCard: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(String(localized: "Changer de mode"))
            SharpitInsetGroup {
                ForEach(ActivityStatusId.allCases, id: \.self) { status in
                    ActivityStatusOptionRow(
                        status: status,
                        isSelected: store.store.status == status
                    ) {
                        Task { await pick(status) }
                    }
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
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                SharpitIconTile(symbol: status.symbolName, size: 40)

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

                SharpitCheckBox(isOn: isSelected)
            }
            .padding(.horizontal, SharpitSpacing.rowPaddingX)
            .padding(.vertical, SharpitSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: SharpitSpacing.rowHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

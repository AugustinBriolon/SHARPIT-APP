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
    /// The scheme the drawer opens in, where the chip itself sits on a forced-dark backdrop.
    var drawerScheme: ColorScheme?
    @Environment(\.colorScheme) private var colorScheme
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
                .environment(\.colorScheme, drawerScheme ?? colorScheme)
        }
        .task { await store.loadIfNeeded() }
    }
}

struct ActivityStatusDrawer: View {
    @Bindable var store: ActivityStatusStore
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellRouter.self) private var router

    /// Mirrors the store while the sheet is open so the date picker can move before
    /// the athlete commits it.
    @State private var untilDate = ActivityStatusDate.defaultUntil()
    @State private var duration = ActivityStatusDuration.untilModified

    private var status: ActivityStatusId { store.store.status }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if case .failed(let message) = store.phase {
                    CliniqueStatusPill(message, status: .watch)
                }
                modes
                if status != .active {
                    effects
                    durationSection
                    actions
                }
            }
            .animation(SharpitMotion.reveal, value: status)
            .animation(SharpitMotion.reveal, value: duration)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, SharpitSpacing.lg)
        }
        // The sheet's one wash, in the mode's tone: the drawer read all white (the athlete's remark, 2026-11-21).
        .cliniqueSheet(wash: status.wash, height: 240)
        .animation(SharpitMotion.reveal, value: status)
        .cliniqueSheetCross { dismiss() }
        .presentationDetents([.medium, .large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
        .onAppear(perform: syncFromStore)
    }

    /// The title, then the mode as a glyph in a ring, its word as a pill, and when it ends.
    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Statut d'activité")
                .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.trailing, 56)
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(SharpitColor.card)
                    Circle().strokeBorder(status.clinique.mark, lineWidth: 3)
                    Image(systemName: status.symbolName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(status.clinique.mark)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    CliniqueStatusPill(status.label, status: status.clinique)
                    if let line = ActivityStatusReadout.resumption(store.store.retention) {
                        Text(line)
                            .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(SharpitColor.slate)
                            .contentTransition(.opacity)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var modes: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(ActivityStatusId.allCases, id: \.self) { mode in
                ActivityStatusModeTile(status: mode, isSelected: status == mode) {
                    Task { await pick(mode) }
                }
            }
        }
    }

    private var effects: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(String(localized: "Ce que ça change"))
                .padding(.bottom, 6)
            CliniqueDivider()
            ForEach(status.effects) { effect in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: effect.symbol)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(status.clinique.mark)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(effect.text)
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                CliniqueDivider()
            }
        }
        .transition(.opacity)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(SharpitTypography.sectionTitle)
            .tracking(SharpitTypography.sectionTitleTracking)
            .foregroundStyle(SharpitColor.foreground)
            .accessibilityAddTraits(.isHeader)
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(String(localized: "Durée"))
            // Two rows, so the chip chosen is never off the edge of a scrolling one.
            VStack(alignment: .leading, spacing: 8) {
                durationRow([.days3, .week1, .weeks2])
                durationRow([.untilModified, .date])
            }
            if duration == .date {
                DatePicker(
                    String(localized: "Reprise prévue"),
                    selection: $untilDate,
                    in: Date.now...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                .tint(SharpitColor.foreground)
                .frame(minHeight: 48)
                .onChange(of: untilDate) { _, _ in
                    Task { await applyRetention() }
                }
            }
        }
    }

    private func durationRow(_ options: [ActivityStatusDuration]) -> some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                ActivityStatusDurationChip(label: option.label, isSelected: duration == option) {
                    Task { await choose(option) }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await pick(.active) }
            } label: {
                Text("Reprendre l'entraînement")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
            Button {
                router.discussWithCoach(about: CoachDiscuss.describe(.planning(horizonDays: 7)))
                dismiss()
            } label: {
                Text("En parler au coach")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CliniqueButtonStyle(kind: .outline))
        }
    }

    private func syncFromStore() {
        duration = ActivityStatusDuration.matching(store.store.retention)
        if let date = ActivityStatusReadout.endDay(store.store.retention) {
            untilDate = date
        }
    }

    private func pick(_ mode: ActivityStatusId) async {
        guard mode != status else { return }
        // A mode picked from « Actif » opens until changed; one picked between two keeps its length.
        if status == .active { duration = .untilModified }
        await write(mode)
    }

    private func choose(_ option: ActivityStatusDuration) async {
        guard option != duration else { return }
        duration = option
        await applyRetention()
    }

    private func applyRetention() async {
        guard status != .active else { return }
        await write(status)
    }

    /// The chips and the picker keep what the athlete set — a day picked seven days out must not
    /// turn into « 1 semaine » under the finger — unless the server refused it.
    private func write(_ mode: ActivityStatusId) async {
        await store.apply(status: mode, retention: duration.retention(picked: untilDate))
        if case .failed = store.phase { syncFromStore() }
    }
}

/// One mode as a tile of the grid: its glyph in its status' tint, its word, the held one ringed in ink.
private struct ActivityStatusModeTile: View {
    let status: ActivityStatusId
    let isSelected: Bool
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: status.symbolName)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(status.clinique.foreground)
                    .frame(width: 40, height: 40)
                    .background(status.clinique.fill, in: Circle())
                    .overlay(Circle().strokeBorder(status.clinique.border, lineWidth: 1))
                    .accessibilityHidden(true)
                Text(status.label)
                    .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SharpitColor.card, in: RoundedRectangle(cornerRadius: SharpitTokens.cardShapeRadius, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SharpitColor.foreground)
                        .padding(14)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: SharpitTokens.cardShapeRadius, style: .continuous)
                    .strokeBorder(isSelected ? SharpitColor.foreground : SharpitColor.divider, lineWidth: isSelected ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(status.label)
        .accessibilityHint(status.hint)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct ActivityStatusDurationChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(minHeight: SharpitSpacing.minimumTouchTarget)
                .background(isSelected ? SharpitColor.primary : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(SharpitColor.outline, lineWidth: isSelected ? 0 : 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

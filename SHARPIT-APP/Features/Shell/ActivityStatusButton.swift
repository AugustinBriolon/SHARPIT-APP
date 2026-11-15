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

struct ActivityStatusDrawer: View {
    @Bindable var store: ActivityStatusStore
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellRouter.self) private var router

    /// Mirrors the store while the sheet is open so the date picker can move before
    /// the athlete commits it.
    @State private var untilDate = ActivityStatusDate.defaultUntil()
    @State private var usesDeadline = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Statut d'activité")
                    .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title))
                    .tracking(-0.4)
                    .foregroundStyle(SharpitColor.foreground)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.trailing, 56)
                if case .failed(let message) = store.phase {
                    CliniqueStatusPill(message, status: .watch)
                }
                statusPlate
                modesCard
                if store.store.status != .active {
                    deadlineSection
                }
            }
            .animation(SharpitMotion.reveal, value: store.store.status)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, SharpitSpacing.lg)
        }
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        .presentationDetents([.medium, .large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
        .onAppear(perform: syncFromStore)
    }

    /// The mode now: its name, until when as a pill, what it changes for the plan and the coach.
    private var statusPlate: some View {
        let status = store.store.status
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: status.symbolName)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(SharpitColor.foreground)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().strokeBorder(SharpitColor.outline, lineWidth: 1))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode actuel")
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(SharpitColor.slate)
                    Text(status.label)
                        .font(SharpitTypography.system(size: 20, weight: .semibold, relativeTo: .title3))
                        .foregroundStyle(SharpitColor.foreground)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                if let until = untilLabel, !typeSize.isAccessibilitySize {
                    CliniqueStatusPill(until, status: .unknown)
                }
            }
            // A pill never shrinks: beside the title at the largest sizes it pushed the plate off screen.
            if let until = untilLabel, typeSize.isAccessibilitySize {
                Text(until)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(status.planningImpact)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .lineSpacing(2)
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
            if status != .active {
                Button("En parler au coach") {
                    router.discussWithCoach(about: CoachDiscuss.describe(.planning(horizonDays: 7)))
                    dismiss()
                }
                .buttonStyle(CliniqueButtonStyle(kind: .outline))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// « 3 nov. » while a mode has an end, nothing when it holds until changed.
    private var untilLabel: String? {
        guard let day = store.store.retention.untilDate,
              let date = ActivityStatusDate.date(from: day) else { return nil }
        return String(localized: "Jusqu'au \(date.sharpitFormatted(.dateTime.day().month(.abbreviated)))")
    }

    private var modesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(String(localized: "Changer de mode"))
            ForEach(Array(ActivityStatusId.allCases.enumerated()), id: \.element) { index, status in
                if index > 0 { CliniqueDivider() }
                ActivityStatusOptionRow(status: status, isSelected: store.store.status == status) {
                    Task { await pick(status) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(SharpitTypography.sectionTitle)
            .tracking(SharpitTypography.sectionTitleTracking)
            .foregroundStyle(SharpitColor.foreground)
            .accessibilityAddTraits(.isHeader)
    }

    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle(String(localized: "Durée"))
            Toggle("Jusqu'à une date", isOn: $usesDeadline)
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout))
                .toggleStyle(SharpitSwitchStyle())
                .frame(minHeight: 48)
                .onChange(of: usesDeadline) { _, isOn in
                    Task { await applyRetention(usesDeadline: isOn) }
                }
            CliniqueDivider()
            if usesDeadline {
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
                    Task { await applyRetention(usesDeadline: true) }
                }
            } else {
                Text("Le mode reste actif jusqu'à ce que tu le changes.")
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(SharpitColor.slate)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onPick) {
            HStack(alignment: .center, spacing: SharpitSpacing.sm) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: status.symbolName)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(SharpitColor.foreground)
                        .frame(width: 36, height: 36)
                        .background(SharpitColor.tile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.label)
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.foreground)
                    // The same line whether or not it is picked: a description that
                    // rewrites itself on selection reads as a different option.
                    Text(status.hint)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(SharpitColor.slate)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                // One mode at a time: the one held carries a check, the others nothing.
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SharpitColor.foreground)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

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

/// The mode's sheet: a wheel of the four modes and nothing else. Turning it sets the mode — no
/// description, no length, no button (the athlete's call, 2026-11-21: the mode is kept day by
/// day, and the list of rows it replaced was another app's).
struct ActivityStatusDrawer: View {
    @Bindable var store: ActivityStatusStore
    @Environment(\.dismiss) private var dismiss

    /// What the wheel shows. It follows the store (a read, a refused write) and writes on a turn.
    @State private var selection = ActivityStatusId.active

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Statut d'activité")
                .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title))
                .tracking(-0.4)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
                .padding(.trailing, 56)

            Picker("Statut d'activité", selection: $selection) {
                ForEach(ActivityStatusId.allCases, id: \.self) { status in
                    HStack(spacing: SharpitSpacing.sm) {
                        Image(systemName: status.symbolName)
                            .foregroundStyle(status.tone)
                        Text(status.label)
                            .foregroundStyle(SharpitColor.foreground)
                    }
                    .font(SharpitTypography.system(size: 22, weight: .semibold, relativeTo: .title3))
                    .tag(status)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            if case .failed(let message) = store.phase {
                CliniqueStatusPill(message, status: .watch)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        .presentationDetents([.height(340)])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
        .onAppear { selection = store.store.status }
        .onChange(of: store.store.status) { _, status in
            if selection != status { selection = status }
        }
        .onChange(of: selection) { _, status in
            guard status != store.store.status else { return }
            // Set from the phone, a mode holds until it is changed: no length is asked here.
            Task { await store.apply(status: status, retention: .untilModified) }
        }
    }
}

import SwiftUI

/// The day's journal: what the athlete did, took or felt, beside the numbers the
/// devices report on their own.
struct JournalView: View {
    @State private var store: JournalStore
    @State private var showsPrefs = false

    init(client: any JournalServing, tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: JournalStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SharpitCanvasBackground())
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsPrefs = true
                    } label: {
                        Label("Personnaliser", systemImage: "slider.horizontal.3")
                    }
                    .disabled(store.phase == .loading)
                }
            }
            .sheet(isPresented: $showsPrefs) {
                JournalPrefsDrawer(store: store)
            }
            .task { await store.load() }
            .onDisappear {
                Task { await store.flushPendingSave() }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            JournalLoadingRows()
        case .failed(let message):
            ContentUnavailableView {
                Label("Journal indisponible", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
        case .ready:
            entries
        }
    }

    private var entries: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                if let failure = store.saveFailure {
                    Text(failure)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalCaution)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if store.hasNothingToShow {
                    ContentUnavailableView {
                        Label("Rien à suivre", systemImage: "book.closed")
                    } description: {
                        Text("Choisis ce que tu veux noter chaque jour.")
                    } actions: {
                        Button("Personnaliser") { showsPrefs = true }
                    }
                    .padding(.top, SharpitSpacing.xl)
                }

                ForEach(JournalCategory.allCases) { category in
                    let trackables = store.visibleTrackables.filter { $0.category == category }
                    if !trackables.isEmpty {
                        JournalSection(title: category.label) {
                            ForEach(trackables) { trackable in
                                JournalTrackableRow(trackable: trackable, store: store)
                            }
                        }
                    }
                }

                if !store.visibleCustomItems.isEmpty {
                    JournalSection(title: "Personnalisé") {
                        ForEach(store.visibleCustomItems) { item in
                            JournalFactorRow(
                                label: item.label,
                                symbolName: JournalCatalogue.customSymbolName,
                                state: store.entry.state(of: item.id)
                            ) { newState in
                                store.set(factorId: item.id, to: newState)
                            }
                        }
                    }
                }
            }
            .padding(SharpitSpacing.pageInset)
        }
    }
}

/// Rows in the shape the journal is about to show. The shared loading instrument
/// draws a verdict plate and gauges, which this screen never has.
private struct JournalLoadingRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Bien-être")
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                    .fill(SharpitColor.analysisSurface)
                    .frame(height: 64)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.pageInset)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Chargement du journal")
    }
}

private struct JournalSection<Content: View>: View {
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

private struct JournalTrackableRow: View {
    let trackable: JournalTrackable
    @Bindable var store: JournalStore

    var body: some View {
        switch trackable.kind {
        case .factor:
            JournalFactorRow(
                label: trackable.label,
                symbolName: trackable.symbolName,
                state: store.entry.state(of: trackable.id)
            ) { newState in
                store.set(factorId: trackable.id, to: newState)
            }
        case .caffeine:
            JournalStepperRow(
                label: trackable.label,
                symbolName: trackable.symbolName,
                value: store.entry.caffeineMg.map { "\($0) mg" } ?? "— mg",
                canDecrement: (store.entry.caffeineMg ?? 0) > 0
            ) { delta in
                store.adjustCaffeine(by: delta * 40)
            }
        case .hydration:
            JournalStepperRow(
                label: trackable.label,
                symbolName: trackable.symbolName,
                value: store.entry.hydrationMl.map { "\($0) ml" } ?? "— ml",
                canDecrement: (store.entry.hydrationMl ?? 0) > 0
            ) { delta in
                store.adjustHydration(by: delta * 250)
            }
        case .mood:
            JournalMoodRow(label: trackable.label, selected: store.mood) { mood in
                store.setMood(mood)
            }
        }
    }
}

/// A yes / no / unanswered signal. Unanswered is its own answer — the analyses only
/// weigh what the athlete actually said — so it stays a visible third choice.
private struct JournalFactorRow: View {
    let label: String
    let symbolName: String
    let state: JournalFactorState
    let onChange: (JournalFactorState) -> Void

    var body: some View {
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

            Spacer(minLength: SharpitSpacing.xs)

            Picker(label, selection: Binding(get: { state }, set: onChange)) {
                Text("—").tag(JournalFactorState.unset)
                Text("Non").tag(JournalFactorState.no)
                Text("Oui").tag(JournalFactorState.yes)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

private struct JournalStepperRow: View {
    let label: String
    let symbolName: String
    let value: String
    let canDecrement: Bool
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: symbolName)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                Text(value)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            Spacer(minLength: 0)

            HStack(spacing: SharpitSpacing.xs) {
                Button {
                    onStep(-1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .disabled(!canDecrement)
                .accessibilityLabel("Retirer")

                Button {
                    onStep(1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Ajouter")
            }
            .font(SharpitTypography.bodyEmphasis)
            .buttonStyle(.plain)
            .foregroundStyle(SharpitColor.primary)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .contain)
        .accessibilityValue(value)
    }
}

private struct JournalMoodRow: View {
    let label: String
    let selected: JournalMood?
    let onPick: (JournalMood?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Text(label)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)

            HStack(spacing: SharpitSpacing.xxs) {
                ForEach(JournalMood.allCases) { mood in
                    Button {
                        onPick(selected == mood ? nil : mood)
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: mood.symbolName)
                                .font(SharpitTypography.body)
                            Text(mood.label)
                                .font(SharpitTypography.meta)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SharpitSpacing.xs)
                        .foregroundStyle(
                            selected == mood ? SharpitColor.primary : SharpitColor.mutedForeground
                        )
                        .sharpitSurface(selected == mood ? .panelAlt : .chip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mood.label)
                    .accessibilityAddTraits(selected == mood ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

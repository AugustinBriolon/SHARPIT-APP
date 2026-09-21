import SwiftUI

/// The day's journal: what the athlete did, took or felt, beside the numbers the
/// devices report on their own.
struct JournalView: View {
    @State private var store: JournalStore
    @State private var showsPrefs = false
    @State private var showsWellness = false

    private let wellness: any WellnessServing
    private let tokenProvider: () async throws -> String

    init(
        client: any JournalServing,
        wellness: any WellnessServing,
        tokenProvider: @escaping () async throws -> String
    ) {
        self.wellness = wellness
        self.tokenProvider = tokenProvider
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
            .sheet(isPresented: $showsWellness) {
                MorningWellnessSheet(
                    client: wellness,
                    tokenProvider: tokenProvider,
                    trainingDayId: store.trainingDayId
                ) { label in
                    store.applyMoodLabel(label)
                }
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
                                JournalTrackableRow(
                                    trackable: trackable,
                                    store: store,
                                    onOpenWellness: { showsWellness = true }
                                )
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
    var onOpenWellness: () -> Void = {}

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
            JournalWellnessRow(label: trackable.label, moodLabel: store.moodLabel, onOpen: onOpenWellness)
        }
    }
}

/// Mood is the visible end of the morning check-in, not a field of its own: tapping it
/// opens the four scales the web asks together.
private struct JournalWellnessRow: View {
    let label: String
    let moodLabel: String?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "face.smiling")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(moodLabel ?? "Ressenti du matin non renseigné")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(
                            moodLabel == nil ? SharpitColor.mutedForeground : SharpitColor.primary
                        )
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .accessibilityHidden(true)
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
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

            JournalAnswerToggle(state: state, onChange: onChange)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

private extension JournalFactorState {
    /// The selection pill follows the answer: a recorded "non" reads red, an unanswered
    /// day stays quiet, a recorded "oui" is what the day now carries.
    var tone: Color {
        switch self {
        case .no: SharpitColor.signalRisk
        case .unset: SharpitElevatedColor.control
        case .yes: SharpitColor.primary
        }
    }

    var onTone: Color {
        switch self {
        case .no: .white
        case .unset: SharpitColor.foreground
        case .yes: SharpitColor.primaryForeground
        }
    }
}

/// Non, unanswered, Oui — in that order. Unanswered is a real third choice and not the
/// absence of one: the analyses only weigh an explicit answer, so an athlete has to be
/// able to go back to "not said".
///
/// The selection is one pill that slides between fixed slots, never a view inserted and
/// removed per segment: an inserted view cross-fades on top of the move, which is what
/// made the answer feel like it arrived late.
private struct JournalAnswerToggle: View {
    let state: JournalFactorState
    let onChange: (JournalFactorState) -> Void

    private static let order: [JournalFactorState] = [.no, .unset, .yes]
    private static let segmentSize = CGSize(width: 42, height: 30)
    private static let inset: CGFloat = 2

    var body: some View {
        HStack(spacing: 0) {
            segment(.no, title: "Non", accessibilityTitle: "Non")
            segment(.unset, title: "—", accessibilityTitle: "Non renseigné")
            segment(.yes, title: "Oui", accessibilityTitle: "Oui")
        }
        .background(alignment: .leading) {
            Capsule()
                .fill(state.tone)
                .frame(width: Self.segmentSize.width, height: Self.segmentSize.height)
                .sharpitShadow(.control)
                .offset(x: CGFloat(Self.order.firstIndex(of: state) ?? 1) * Self.segmentSize.width)
        }
        .padding(Self.inset)
        .background(Capsule().fill(SharpitColor.analysisGrid))
        .animation(SharpitMotion.selection, value: state)
    }

    private func segment(
        _ value: JournalFactorState,
        title: String,
        accessibilityTitle: String
    ) -> some View {
        let isSelected = state == value
        return Button {
            onChange(value)
        } label: {
            Text(title)
                .font(SharpitTypography.meta)
                .foregroundStyle(isSelected ? value.onTone : SharpitColor.mutedForeground)
                .frame(width: Self.segmentSize.width, height: Self.segmentSize.height)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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
                    .contentTransition(.numericText())
                    .animation(SharpitMotion.selection, value: value)
            }

            Spacer(minLength: 0)

            HStack(spacing: SharpitSpacing.xs) {
                Button {
                    onStep(-1)
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 34, height: 34)
                        .background(SharpitColor.primary.opacity(0.12), in: Circle())
                        .contentShape(.circle)
                }
                .buttonStyle(.sharpitPressable)
                .disabled(!canDecrement)
                .accessibilityLabel("Retirer")

                Button {
                    onStep(1)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 34, height: 34)
                        .background(SharpitColor.primary.opacity(0.12), in: Circle())
                        .contentShape(.circle)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityLabel("Ajouter")
            }
            .font(SharpitTypography.bodyEmphasis)
            .foregroundStyle(SharpitColor.primary)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .contain)
        .accessibilityValue(value)
    }
}

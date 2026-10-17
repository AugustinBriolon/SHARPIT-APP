import SwiftUI

/// Simplified morning wellness & mood check-in drawer.
/// Presents all 4 dimensions on a single half-screen sheet with an intuitive 1–5 scale.
struct MorningWellnessSheet: View {
    @State private var store: MorningWellnessStore
    /// The mood label the check-in produced, so the journal can echo it.
    let onCompleted: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?

    init(
        client: any WellnessServing,
        tokenProvider: @escaping () async throws -> String,
        trainingDayId: String,
        onSaved: @escaping @MainActor () -> Void = {},
        onCompleted: @escaping (String) -> Void
    ) {
        _store = State(
            initialValue: MorningWellnessStore(
                client: client,
                tokenProvider: tokenProvider,
                trainingDayId: trainingDayId,
                onSaved: onSaved
            )
        )
        self.onCompleted = onCompleted
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(SharpitCanvasBackground())
                .navigationTitle("Humeur & Ressenti")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
        }
        .presentationDetents([.fraction(0.8), .large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
        .task { await store.load() }
        .onChange(of: store.phase) { _, phase in
            if case .failed(let message) = phase, !store.picks.isEmpty {
                toastCenter?.show(
                    message,
                    symbol: "exclamationmark.triangle.fill",
                    tone: .error,
                    autoDismissAfter: 3.5
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            WellnessLoadingSkeleton()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .failed(let message) where store.picks.isEmpty:
            ContentUnavailableView {
                Label("Ressenti indisponible", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
        case .ready, .failed:
            ScrollView {
                VStack(spacing: SharpitSpacing.sm) {
                    VStack(spacing: SharpitSpacing.xs) {
                        ForEach(WellnessDimension.allCases) { dimension in
                            WellnessDimensionRow(
                                dimension: dimension,
                                selected: store.picks[dimension],
                                onPick: { score in
                                    store.pick(score, for: dimension)
                                }
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                        Text("Note pour le coach (optionnel)")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                        TextField("Détail sur ta nuit, sensation particulière…", text: $store.notes, axis: .vertical)
                            .lineLimit(2...3)
                            .font(SharpitTypography.body)
                            .padding(SharpitSpacing.sm)
                            .sharpitSurface(.panel)
                    }
                    .padding(.top, SharpitSpacing.xxs)

                }
                .padding(SharpitSpacing.pageInset)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Docked, so « Enregistrer » is never cut by the sheet's height.
            .safeAreaInset(edge: .bottom) {
                SharpitPrimaryButton(title: "Enregistrer", trailingSymbol: "checkmark") {
                    guard let label = store.submit() else { return }
                    onCompleted(label)
                    dismiss()
                }
                .disabled(!store.canSubmit)
                .opacity(store.canSubmit ? 1 : 0.45)
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.vertical, SharpitSpacing.sm)
                .background(SharpitColor.background)
            }
        }
    }
}

private struct WellnessDimensionRow: View {
    let dimension: WellnessDimension
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selected: WellnessScore?
    let onPick: (WellnessScore) -> Void

    private var iconName: String {
        switch dimension {
        case .mood: "face.smiling"
        case .energy: "bolt.fill"
        case .soreness: "figure.walk"
        case .stress: "heart.text.square"
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At the accessibility sizes the scores go under the title: beside it, the 72 pt
                // title column broke words and the five scores ran off the screen.
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    HStack(spacing: SharpitSpacing.sm) {
                        JournalRowIcon(symbolName: iconName)
                        titles
                    }
                    scores
                }
            } else {
                HStack(spacing: SharpitSpacing.sm) {
                    JournalRowIcon(symbolName: iconName)
                    titles.frame(width: 72, alignment: .leading)
                    Spacer(minLength: SharpitSpacing.xxs)
                    scores
                }
            }
        }
        .padding(.horizontal, SharpitSpacing.cardPadding)
        .padding(.vertical, 10)
        .sharpitSurface(.panel)
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dimension.title)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)

            Text(selected.map { dimension.label(for: $0) } ?? "Choisir")
                .font(SharpitTypography.meta)
                .foregroundStyle(selected != nil ? SharpitColor.foreground : SharpitColor.mutedForeground)
                .lineLimit(1)
        }
    }

    private var scores: some View {
        HStack(spacing: 6) {
            ForEach(WellnessScore.allCases) { score in
                let isSelected = selected == score
                Button {
                    onPick(score)
                } label: {
                    Text("\(score.rawValue)")
                        .font(.system(size: 15, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? SharpitColor.primaryForeground : SharpitColor.foreground)
                        .frame(width: 35, height: 35)
                        .background(
                            isSelected ? SharpitColor.primary : SharpitColor.secondary.opacity(0.4),
                            in: Circle()
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? Color.white.opacity(0.2) : SharpitColor.analysisBorder.opacity(0.5), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(dimension.title) \(score.rawValue) sur 5, \(dimension.label(for: score))")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}

private struct WellnessLoadingSkeleton: View {
    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: SharpitSpacing.sm) {
                    Circle()
                        .fill(SharpitColor.analysisSurfaceAlt)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SharpitColor.analysisSurfaceAlt)
                            .frame(width: 60, height: 14)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(SharpitColor.analysisSurfaceAlt)
                            .frame(width: 44, height: 10)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        ForEach(0..<5, id: \.self) { _ in
                            Circle()
                                .fill(SharpitColor.analysisSurfaceAlt)
                                .frame(width: 35, height: 35)
                        }
                    }
                }
                .padding(.horizontal, SharpitSpacing.cardPadding)
                .padding(.vertical, 10)
                .sharpitSurface(.panel)
            }
        }
        .padding(SharpitSpacing.pageInset)
        .redacted(reason: .placeholder)
    }
}

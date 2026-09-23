import SwiftUI

/// What a screen hands the drawer so it can link its prescription.
///
/// Optional on the drawer: a fixture-backed Today has no token and nothing to link against,
/// and a control that cannot work is worse than no control.
struct SessionLinkContext {
    /// The day the prescription belongs to, which is where candidates are looked for.
    let referenceDate: Date
    let activities: any ActivityServing
    let linker: any PlannedSessionLinking
    let tokenProvider: () async throws -> String
    /// Called once a link is made, so the screen behind can show the session as done.
    let onLinked: () -> Void
}

/// The activities a prescription can be linked to, in a sheet.
struct SessionLinkPicker: View {
    @State private var store: SessionLinkStore
    let onLinked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?

    init(sessionId: String, context: SessionLinkContext, onLinked: @escaping () -> Void) {
        _store = State(
            initialValue: SessionLinkStore(
                sessionId: sessionId,
                referenceDate: context.referenceDate,
                activities: context.activities,
                linker: context.linker,
                tokenProvider: context.tokenProvider
            )
        )
        self.onLinked = onLinked
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(SharpitCanvasBackground())
                .navigationTitle("Séance réalisée")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
        .task { await store.load() }
        .onChange(of: store.phase) { _, phase in
            if case .failed(let message) = phase, !store.candidates.isEmpty {
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
            SharpitLoadingInstrument()
        case .failed(let message) where store.candidates.isEmpty:
            ContentUnavailableView {
                Label("Chargement impossible", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
        case .ready where store.candidates.isEmpty:
            ContentUnavailableView(
                "Rien à rapprocher",
                systemImage: "tray",
                description: Text("Aucune séance réalisée sans séance prévue la veille, ce jour-là ou le lendemain.")
            )
        case .ready, .linking, .failed:
            list
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                SharpitEyebrow("Choisis la séance qui l'a réalisée")
                ForEach(store.candidates) { candidate in
                    Button {
                        Task {
                            guard await store.link(candidate) else { return }
                            SharpitHaptics.play(.soft)
                            onLinked()
                        }
                    } label: {
                        SessionLinkCandidateRow(candidate: candidate)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.phase == .linking)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SharpitSpacing.pageInset)
        }
        .opacity(store.phase == .linking ? 0.6 : 1)
    }
}

private struct SessionLinkCandidateRow: View {
    let candidate: SessionLinkCandidate

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: candidate.symbolName)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitSportTone.label(for: candidate.sport))
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .multilineTextAlignment(.leading)
                Text([candidate.sport, candidate.durationLabel, candidate.dayLabel]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }

            Spacer(minLength: 0)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

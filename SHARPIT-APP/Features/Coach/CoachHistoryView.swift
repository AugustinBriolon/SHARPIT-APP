import SwiftUI

/// Past conversations, in a sheet.
struct CoachHistoryView: View {
    @State private var store: CoachHistoryStore
    let currentConversationId: String?
    let onOpen: (CoachConversationSummary) -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        store: CoachHistoryStore,
        currentConversationId: String?,
        onOpen: @escaping (CoachConversationSummary) -> Void
    ) {
        _store = State(initialValue: store)
        self.currentConversationId = currentConversationId
        self.onOpen = onOpen
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SharpitCanvasBackground())
                .navigationTitle("Historique")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            SharpitLoadingInstrument()
        case .failed(let message):
            ContentUnavailableView {
                Label("Historique indisponible", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
        case .loaded(let conversations) where conversations.isEmpty:
            ContentUnavailableView(
                "Aucune conversation",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Tes échanges avec le coach apparaîtront ici.")
            )
        case .loaded(let conversations):
            list(conversations)
        }
    }

    private func list(_ conversations: [CoachConversationSummary]) -> some View {
        List {
            if let failure = store.deletionFailure {
                Text(failure)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalCaution)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(conversations) { conversation in
                Button {
                    onOpen(conversation)
                    dismiss()
                } label: {
                    CoachHistoryRow(
                        conversation: conversation,
                        isCurrent: conversation.id == currentConversationId
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: SharpitSpacing.xxs,
                    leading: SharpitSpacing.pageInset,
                    bottom: SharpitSpacing.xxs,
                    trailing: SharpitSpacing.pageInset
                ))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await store.delete(conversation) }
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

private struct CoachHistoryRow: View {
    let conversation: CoachConversationSummary
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(conversation.title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(ActivityFormat.dayLabel(for: conversation.updatedAt))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            Spacer(minLength: 0)
            if isCurrent {
                Circle()
                    .fill(SharpitColor.primary)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Conversation ouverte")
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

import SwiftUI

/// Past conversations, in a sheet.
struct CoachHistoryView: View {
    @State private var store: CoachHistoryStore
    let currentConversationId: String?
    let onOpen: (CoachConversationSummary) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?

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
        VStack(alignment: .leading, spacing: 8) {
            CliniqueSheetTitle(String(localized: "Historique"))
                .padding(.horizontal, 24)
                .padding(.top, 30)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SharpitColor.card)
        .cliniqueSheetCross { dismiss() }
        .presentationDetents([.medium, .large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
        .task { await store.load() }
        .onChange(of: store.deletionFailure) { _, failure in
            if let failure {
                toastCenter?.show(
                    failure,
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
            // The list's own rows, redacted: the history opens in the shape it will take.
            list(CoachConversationSummary.placeholders)
                .redacted(reason: .placeholder)
                .allowsHitTesting(false)
                .accessibilityLabel("Chargement de l'historique")
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
                String(localized: "Aucune conversation"),
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Tes échanges avec le coach apparaîtront ici.")
            )
        case .loaded(let conversations):
            list(conversations)
        }
    }

    private func list(_ conversations: [CoachConversationSummary]) -> some View {
        List {
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
                .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                .swipeActions(edge: .trailing) {
                    SharpitSwipeDeleteButton {
                        Task { await store.delete(conversation) }
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
        VStack(spacing: 0) {
            HStack(spacing: SharpitSpacing.sm) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.title)
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ActivityFormat.dayLabel(for: conversation.updatedAt))
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    CliniqueStatusPill(String(localized: "Ouverte"), status: .pro)
                }
            }
            .padding(.vertical, 14)
            CliniqueDivider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private extension CoachConversationSummary {
    static let placeholders: [CoachConversationSummary] = (0..<6).map { index in
        CoachConversationSummary(
            id: "skeleton-\(index)",
            title: String(localized: "Conversation avec le coach sur la semaine"),
            updatedAt: Date(timeIntervalSinceNow: -Double(index) * 86_400)
        )
    }
}

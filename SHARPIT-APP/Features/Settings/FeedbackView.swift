import SwiftUI

/// « Donner un avis »: the note shows as sent on the tap and goes out behind, retried; only a
/// note that fails for good is said, in the app's toast — the page may be closed by then.
@MainActor
@Observable
final class FeedbackStore {
    var message = ""
    private(set) var isSent = false

    private let client: any FeedbackServing
    private let tokenProvider: () async throws -> String
    private let context: String

    init(
        client: any FeedbackServing = FeedbackClient(),
        tokenProvider: @escaping () async throws -> String,
        context: String = "settings"
    ) {
        self.client = client
        self.tokenProvider = tokenProvider
        self.context = context
    }

    var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSent
    }

    /// Returns once the note reached the server or failed for good.
    func send() async {
        guard canSend else { return }
        let note = V1FeedbackNote(
            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
            context: context,
            appVersion: AppVersion.display
        )
        isSent = true
        do {
            try await SharpitRetry.run {
                try await client.sendFeedback(note, token: try await tokenProvider())
            }
            message = ""
        } catch {
            isSent = false
            SharpitWriteFailures.shared.report(Self.failureMessage(for: error))
        }
    }

    /// Writes another note after the first went out.
    func startOver() {
        isSent = false
        message = ""
    }

    static func failureMessage(for error: Error) -> String {
        if case SharpitAPIError.message(let text) = error { return text }
        if case SharpitAPIError.rateLimited = error { return "Beaucoup d’avis d’un coup : réessaie dans un moment." }
        return "Ton avis n’est pas parti. Réessaie dans un instant."
    }
}

struct FeedbackView: View {
    @State private var store: FeedbackStore
    @FocusState private var isWriting: Bool

    init(tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: FeedbackStore(tokenProvider: tokenProvider))
    }

    var body: some View {
        List {
            if store.isSent {
                sent
            } else {
                writing
            }
        }
        .sharpitGroupedList()
        .navigationTitle("Donner un avis")
        .navigationBarTitleDisplayMode(.inline)
        .animation(SharpitMotion.reveal, value: store.isSent)
    }

    private var writing: some View {
        Section(
            eyebrow: "Ton avis",
            footer: "Un truc qui coince, une idée, une envie ? Écris-le comme ça vient : je lis tout. Ton message part avec ton identifiant SharpIt et la version de l’app, rien d’autre."
        ) {
            TextEditor(text: $store.message)
                .focused($isWriting)
                .frame(minHeight: 160)
                .font(SharpitTypography.body)
                .overlay(alignment: .topLeading) {
                    if store.message.isEmpty {
                        Text("Ce matin, la proposition d’allègement…")
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            Button("Envoyer") {
                isWriting = false
                Task { await store.send() }
            }
            .font(SharpitTypography.bodyEmphasis)
            .disabled(!store.canSend)
        }
        .sharpitListRows()
        .onAppear { isWriting = true }
    }

    private var sent: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Merci, c’est bien arrivé")
                        .font(SharpitTypography.bodyEmphasis)
                    Text("Je lis chaque avis. Ce qui revient souvent passe en priorité.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(SharpitColor.signalRecovery)
            }
            Button("Écrire autre chose") { store.startOver() }
        }
        .sharpitListRows()
    }
}

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
    /// Bumped as the confirmation arrives, so its seal bounces once.
    @State private var sealArrival = 0

    /// The keyboard goes down before the page changes: both at once read as a jolt.
    private static let keyboardDismissal: Duration = .milliseconds(250)

    init(tokenProvider: @escaping () async throws -> String) {
        _store = State(initialValue: FeedbackStore(tokenProvider: tokenProvider))
    }

    var body: some View {
        ZStack {
            if store.isSent {
                confirmation
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.94).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                form
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharpitElevatedColor.groupedCanvas.ignoresSafeArea())
        .navigationTitle("Donner un avis")
        .navigationBarTitleDisplayMode(.inline)
        .animation(SharpitMotion.reveal, value: store.isSent)
        .onChange(of: store.isSent) { _, sent in
            guard sent else { return }
            SharpitHaptics.play(.success)
            sealArrival += 1
        }
    }

    private var form: some View {
        List {
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
                Button("Envoyer", action: send)
                    .font(SharpitTypography.bodyEmphasis)
                    .disabled(!store.canSend)
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .onAppear { isWriting = true }
    }

    private var confirmation: some View {
        VStack(spacing: SharpitSpacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(SharpitColor.signalRecovery)
                .symbolEffect(.bounce, value: sealArrival)
            VStack(spacing: SharpitSpacing.xs) {
                Text("Merci, c’est bien arrivé")
                    .font(SharpitTypography.cardTitle)
                    .foregroundStyle(SharpitColor.foreground)
                Text("Je lis chaque avis. Ce qui revient souvent passe en priorité.")
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
            }
            Button("Écrire autre chose") { store.startOver() }
                .font(SharpitTypography.bodyEmphasis)
                .padding(.top, SharpitSpacing.xs)
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .accessibilityElement(children: .contain)
    }

    private func send() {
        isWriting = false
        Task {
            try? await Task.sleep(for: Self.keyboardDismissal)
            await store.send()
        }
    }
}

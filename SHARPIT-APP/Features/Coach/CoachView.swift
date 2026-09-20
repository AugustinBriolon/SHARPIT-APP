import SwiftUI

/// The coach conversation.
///
/// A thread and a composer — the shape every chat has, because the athlete already knows
/// how to read it. What is not borrowed from a generic chat: no avatars, no typing dots
/// pretending to be a person, no sparkle chrome. The coach is an instrument that answers
/// in prose, and the design law keeps chatbot decoration off product surfaces.
struct CoachView: View {
    @Environment(ShellRouter.self) private var router
    @State private var store: CoachStore

    init(client: any CoachChatServing, tokenProvider: (() async throws -> String)?) {
        _store = State(initialValue: CoachStore(client: client, tokenProvider: tokenProvider))
    }

    var body: some View {
        NavigationStack {
            thread
                // A bar rather than a stacked row: the system then knows the composer is
                // chrome and keeps the tab bar below it instead of over it.
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .background(SharpitCanvasBackground())
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LiquidNavChrome())
        }
        // The subject travels from wherever the athlete pressed "discuter", and is taken
        // once so returning later cannot silently re-attach a stale one.
        .task(id: router.pendingCoachContext) {
            if let context = router.consumeCoachContext() {
                store.attach(context)
            }
        }
    }

    private var thread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SharpitSpacing.md) {
                    if store.isEmpty {
                        CoachEmptyState()
                    }
                    ForEach(store.messages) { message in
                        CoachMessageRow(message: message, isStreaming: isStreaming(message))
                            .id(message.id)
                    }
                    if let failure = store.failure {
                        Text(failure)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.signalCaution)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, SharpitSpacing.pageInset)
                .padding(.vertical, SharpitSpacing.md)
            }
            .modifier(ScrollUnderGlass())
            // Anchored to the bottom only once there is a thread to follow; an empty
            // screen anchored there pins its invitation to the composer.
            .defaultScrollAnchor(store.isEmpty ? .top : .bottom)
            .onChange(of: store.messages.last?.text) { _, _ in
                guard let last = store.messages.last?.id else { return }
                withAnimation(SharpitMotion.reveal) { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    /// The last assistant turn, while it is still filling in.
    private func isStreaming(_ message: CoachMessage) -> Bool {
        store.isReplying && message.role == .assistant && message.id == store.messages.last?.id
    }

    private var composer: some View {
        VStack(spacing: SharpitSpacing.xs) {
            if let context = store.pendingContext {
                CoachContextTag(context: context) { store.dropContext() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .bottom, spacing: SharpitSpacing.xs) {
                TextField("Pose ta question", text: $store.draft, axis: .vertical)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .lineLimit(1...5)
                    .padding(.horizontal, SharpitSpacing.md)
                    .padding(.vertical, SharpitSpacing.sm)
                    .background(SharpitColor.analysisSurfaceAlt, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            SharpitColor.analysisBorder,
                            lineWidth: SharpitStroke.hairline
                        )
                    )
                    .submitLabel(.send)

                Button {
                    Task { await store.send() }
                } label: {
                    Image(systemName: store.isReplying ? "stop.fill" : "arrow.up")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.primaryForeground)
                        .frame(width: 40, height: 40)
                        .background(
                            store.canSend ? SharpitColor.primary : SharpitColor.radialTrack,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!store.canSend)
                .accessibilityLabel("Envoyer")
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.xs)
        .padding(.bottom, SharpitSpacing.sm)
        .background(.bar)
    }
}

/// A turn. The athlete's is a chip on the right; the coach's is prose on the canvas.
///
/// Only one side gets a bubble on purpose: the coach's answers are the content of this
/// screen, and wrapping them in a container would make them look like remarks.
private struct CoachMessageRow: View {
    let message: CoachMessage
    let isStreaming: Bool

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: SharpitSpacing.xxs) {
                if let context = message.context {
                    CoachContextTag(context: context)
                }
                Text(message.text)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, SharpitSpacing.md)
                    .padding(.vertical, SharpitSpacing.sm)
                    .background(
                        SharpitColor.inkSurface,
                        in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                    )
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

        case .assistant:
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                SharpitEyebrow("Coach")
                Text(message.text)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if isStreaming {
                    CoachWritingMark()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A single pulsing mark while the answer arrives.
///
/// One mark, not three bouncing dots: it says the machine is working without performing
/// a person typing.
private struct CoachWritingMark: View {
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(SharpitColor.primary)
            .frame(width: 7, height: 7)
            .opacity(dim ? 0.25 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: dim)
            .onAppear { dim = true }
            .accessibilityLabel("Le coach répond")
    }
}

private struct CoachEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            Text("Demande ce que tu veux comprendre")
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            Text(
                """
                Une séance, ta semaine, un signal du jour. \
                Depuis un écran, le bouton « discuter » joint le sujet à ta question.
                """
            )
            .font(SharpitTypography.body)
            .foregroundStyle(SharpitColor.mutedForeground)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

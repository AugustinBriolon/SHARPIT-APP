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
    @State private var showingHistory = false
    @FocusState private var composerIsFocused: Bool

    private let conversations: any CoachConversationServing
    private let tokenProvider: (() async throws -> String)?

    init(
        client: any CoachChatServing,
        conversations: any CoachConversationServing,
        tokenProvider: (() async throws -> String)?
    ) {
        self.conversations = conversations
        self.tokenProvider = tokenProvider
        _store = State(
            initialValue: CoachStore(
                client: client,
                conversations: conversations,
                tokenProvider: tokenProvider
            )
        )
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        composerIsFocused = false
                        showingHistory = true
                    } label: {
                        Label("Historique", systemImage: "clock.arrow.circlepath")
                    }
                    .disabled(tokenProvider == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.startNewConversation()
                    } label: {
                        Label("Nouvelle conversation", systemImage: "square.and.pencil")
                    }
                    // Nothing to leave when the thread is empty, and an answer arriving
                    // would land in the conversation the athlete just walked out of.
                    .disabled(store.isEmpty || store.isReplying)
                }
            }
            .sheet(isPresented: $showingHistory) {
                if let tokenProvider {
                    CoachHistoryView(
                        store: CoachHistoryStore(
                            conversations: conversations,
                            tokenProvider: tokenProvider,
                            onDeleted: { store.forget(conversationId: $0) }
                        ),
                        currentConversationId: store.conversationId
                    ) { summary in
                        Task { await store.open(conversationId: summary.id) }
                    }
                }
            }
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
            // Reading is the signal that writing is over: the keyboard follows the drag
            // down rather than waiting to be dismissed.
            .scrollDismissesKeyboard(.interactively)
            // Anchored to the bottom only once there is a thread to follow; an empty
            // screen anchored there pins its invitation to the composer.
            .defaultScrollAnchor(store.isEmpty ? .top : .bottom)
            .onChange(of: store.messages.last?.text) { _, _ in
                scrollToLatest(proxy)
            }
            // The keyboard going down uncovers the thread; the newest turn is what the
            // athlete was writing about, so it is what should be under their eyes.
            .onChange(of: composerIsFocused) { _, focused in
                guard !focused else { return }
                scrollToLatest(proxy)
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let last = store.messages.last?.id else { return }
        withAnimation(SharpitMotion.reveal) { proxy.scrollTo(last, anchor: .bottom) }
    }

    /// The last assistant turn, while it is still filling in.
    private func isStreaming(_ message: CoachMessage) -> Bool {
        store.isReplying && message.role == .assistant && message.id == store.messages.last?.id
    }

    /// The composer's one height — the smallest tappable size, for the field and both circles.
    private static let controlHeight = SharpitSpacing.minimumTouchTarget

    private var composer: some View {
        VStack(spacing: SharpitSpacing.xs) {
            if let context = store.pendingContext {
                CoachContextTag(context: context) { store.dropContext() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SharpitGlassGroup {
                HStack(alignment: .bottom, spacing: SharpitSpacing.xs) {
                    // The explicit way down, for the athlete who is neither scrolling nor
                    // sending. In the row rather than in a keyboard toolbar, which floated
                    // over the send button. Only while writing — otherwise it is a control
                    // that does nothing.
                    if composerIsFocused {
                        Button {
                            composerIsFocused = false
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(SharpitTypography.bodyEmphasis)
                                .foregroundStyle(SharpitColor.mutedForeground)
                                .frame(width: Self.controlHeight, height: Self.controlHeight)
                                .sharpitGlassControl(in: Circle(), fallback: SharpitColor.analysisSurfaceAlt)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Masquer le clavier")
                        .transition(.scale.combined(with: .opacity))
                    }

                    TextField("Pose ta question", text: $store.draft, axis: .vertical)
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        .lineLimit(1...5)
                        .focused($composerIsFocused)
                        // A vertical-axis field treats Return as a newline, so `onSubmit`
                        // never fires. Catching the newline is what makes Return behave the
                        // way the keyboard's own key promises.
                        .onChange(of: store.draft) { _, new in
                            guard new.contains("\n") else { return }
                            store.draft = new.replacingOccurrences(of: "\n", with: "")
                            submit()
                        }
                        .padding(.horizontal, SharpitSpacing.md)
                        .padding(.vertical, SharpitSpacing.xs + 2)
                        // One line is exactly as tall as the circles beside it, so the three
                        // controls share a centre; more lines grow upward from that base.
                        .frame(minHeight: Self.controlHeight)
                        .sharpitGlassControl(in: Capsule(), fallback: SharpitColor.analysisSurfaceAlt)
                        .submitLabel(.send)

                    Button(action: submit) {
                        Image(systemName: store.isReplying ? "stop.fill" : "arrow.up")
                            .font(SharpitTypography.bodyEmphasis)
                            // Untinted glass is light: the arrow goes muted there, not white.
                            .foregroundStyle(store.canSend ? SharpitColor.primaryForeground : SharpitColor.mutedForeground)
                            .frame(width: Self.controlHeight, height: Self.controlHeight)
                            .contentTransition(.symbolEffect(.replace))
                            .sharpitGlassControl(
                                in: Circle(),
                                tint: store.canSend ? SharpitColor.primary : nil,
                                fallback: SharpitColor.radialTrack
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canSend)
                    .accessibilityLabel("Envoyer")
                    .animation(SharpitMotion.selection, value: store.canSend)
                }
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.xs)
        .padding(.bottom, SharpitSpacing.sm)
        .animation(SharpitMotion.reveal, value: composerIsFocused)
    }

    /// Return and the send button do the same thing: put the keyboard away, and send when
    /// there is something to send. Lowering it on an empty field is deliberate — the
    /// athlete asked to stop writing, and the thread is what they want to see.
    private func submit() {
        composerIsFocused = false
        guard store.canSend else { return }
        Task { await store.send() }
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
                // The coach writes markdown; rendering it as literal asterisks would be
                // the app failing to read its own answer.
                SharpitMarkdownText(markdown: message.text)
                    .textSelection(.enabled)
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

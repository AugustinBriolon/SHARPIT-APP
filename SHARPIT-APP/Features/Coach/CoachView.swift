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
    /// What the coach keeps about the athlete — free context, trips, constraints — moved here
    /// from Moi, beside the conversation that reads it.
    @State private var showingMemory = false
    @FocusState private var composerIsFocused: Bool
    @State private var showsJumpToLatest = false
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var dictation = CoachDictation()
    /// Set by a send, so only a question just asked rises to the top.
    @State private var risesOnSend = false

    private let conversations: any CoachConversationServing
    private let tokenProvider: (() async throws -> String)?
    #if DEBUG
    /// Questions asked by themselves, one after the other — the simulator demo only.
    var demoQuestions: [String] = []
    #endif

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
            ZStack(alignment: .bottom) {
                thread
                if showsJumpToLatest {
                    jumpToLatestButton
                        .padding(.bottom, SharpitSpacing.sm)
                }
            }
                // A bar rather than a stacked row: the system then knows the composer is
                // chrome and keeps the tab bar below it instead of over it.
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .onDisappear { dictation.stop() }
                .background(SharpitCanvasBackground())
                #if DEBUG
                .task { await askDemoQuestions() }
                #endif
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        composerIsFocused = false
                        showingMemory = true
                    } label: {
                        Label("Mémoire", systemImage: "brain.head.profile")
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
            .sheet(isPresented: $showingMemory) {
                if let tokenProvider {
                    NavigationStack {
                        CoachMemoryView(client: CoachMemoryClient(), tokenProvider: tokenProvider)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("OK") { showingMemory = false }
                                }
                            }
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .sharpitSheet()
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
        // A change the coach carried out reloads Plan and Résumé, as the web invalidates its
        // planned-session queries after a coach turn.
        .onAppear {
            store.onCalendarChanged = { [router] in router.noteCalendarChanged() }
        }
        .task(id: router.pendingCoachContext) {
            if let context = router.consumeCoachContext() {
                store.attach(context)
            }
        }
    }

    /// The thread reads like a conversation, not a log: a question sent rises to the top of the
    /// screen and its answer unrolls below it, the view never moving on its own while the coach
    /// writes. Once the answer runs past the bottom, an arrow above the composer takes the
    /// athlete down, when they choose to follow.
    private var thread: some View {
        ScrollView {
            let turns = CoachThreadLayout(messages: store.messages)
            // Not lazy: a thread is a few dozen turns, and a lazy stack lost the position it
            // was scrolled to whenever a row it had not laid out changed.
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                if store.isEmpty {
                    CoachEmptyState()
                }
                ForEach(turns.earlier) { message in
                    messageRow(message)
                }
                // The turn under way fills at least the screen, so its question can rise
                // to the top even while its answer is still one line.
                ZStack(alignment: .top) {
                    if !turns.current.isEmpty {
                        Color.clear
                            .containerRelativeFrame(.vertical) { length, _ in
                                max(0, length - SharpitSpacing.md * 2)
                            }
                    }
                    VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                        ForEach(turns.current) { message in
                            messageRow(message)
                        }
                        if let failure = store.failure {
                            Text(failure)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.signalCaution)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                // Every child of the layout carries an id, the turn under way included: the
                // scroll position is kept by id, and a child without one sent it back to the top.
                .id(CoachThreadLayout.turnId(turns.current.first?.id))
                Color.clear
                    .frame(height: 1)
                    .id(CoachThreadLayout.endId)
            }
            .scrollTargetLayout()
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .scrollPosition($scrollPosition)
        // A thumb moving on the thread puts the keyboard away at once — even on an empty
        // conversation, which bounces so the gesture always registers. Before the glass
        // modifier, whose size-based bounce would otherwise win.
        .scrollDismissesKeyboard(.immediately)
        .scrollBounceBehavior(.always, axes: .vertical)
        .modifier(ScrollUnderGlass())
        // Opens at the latest turn, and only then: anchored for size changes too, the view
        // followed every word the coach wrote.
        .defaultScrollAnchor(store.isEmpty ? .top : .bottom, for: .initialOffset)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            CoachThreadLayout.showsJumpToLatest(
                contentHeight: geometry.contentSize.height,
                visibleBottom: geometry.visibleRect.maxY - geometry.contentInsets.bottom
            )
        } action: { _, shows in
            withAnimation(SharpitMotion.selection) { showsJumpToLatest = shows }
        }
        // A question just sent rises to the top; an opened conversation stays at its end.
        .onChange(of: store.messages.last(where: { $0.role == .user })?.id) { _, id in
            guard risesOnSend, let id else { return }
            risesOnSend = false
            // Once the new turn is laid out at its full height: scrolled before, the view
            // stopped at the old end of the thread, halfway up.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(SharpitMotion.reveal) {
                    scrollPosition.scrollTo(id: CoachThreadLayout.turnId(id), anchor: .top)
                }
            }
        }
    }

    private func messageRow(_ message: CoachMessage) -> some View {
        CoachMessageRow(
            message: message,
            isStreaming: isStreaming(message),
            onAnswer: answerHandler
        )
        .id(message.id)
    }

    /// Answers a proposal card; nil while a reply streams, so the buttons wait with it.
    private var answerHandler: ((String, Bool) -> Void)? {
        guard !store.isReplying else { return nil }
        let store = store
        return { approvalId, approved in
            Task { await store.respond(to: approvalId, approved: approved) }
        }
    }

    /// The last assistant turn, while it is still filling in.
    private func isStreaming(_ message: CoachMessage) -> Bool {
        store.isReplying && message.role == .assistant && message.id == store.messages.last?.id
    }

    /// The composer's one height — the smallest tappable size, for the field and both circles.
    private static let controlHeight = SharpitSpacing.minimumTouchTarget

    private var composer: some View {
        VStack(spacing: SharpitSpacing.xs) {
            if let failure = dictation.failure {
                Text(failure)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalCaution)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let context = store.pendingContext {
                CoachContextTag(context: context) { store.dropContext() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SharpitGlassGroup {
                HStack(alignment: .bottom, spacing: SharpitSpacing.xs) {
                    TextField(
                        store.hasPendingApproval ? "Réponds à la proposition, ou écris pour l'ignorer" : "Pose ta question",
                        text: $store.draft,
                        axis: .vertical
                    )
                        .font(SharpitTypography.body)
                        .foregroundStyle(SharpitColor.foreground)
                        // Grows with the text up to six lines, then scrolls inside itself.
                        .lineLimit(1...6)
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
                        // A fixed corner, not a capsule: on one line it reads as a capsule, and
                        // as it grows it becomes a rounded field whose corners never eat the text.
                        .sharpitGlassControl(
                            in: RoundedRectangle(cornerRadius: Self.controlHeight / 2, style: .continuous),
                            fallback: SharpitColor.analysisSurfaceAlt
                        )
                        .animation(SharpitMotion.selection, value: store.draft.count / 40)
                        .submitLabel(.send)

                    composerButton
                }
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.xs)
        .padding(.bottom, SharpitSpacing.sm)
        .animation(SharpitMotion.reveal, value: composerIsFocused)
    }

    /// Small, and glass as the composer under it. Plain glass: interactive glass, on the label
    /// or through the system's glass button, kept the tap for itself here.
    private var jumpToLatestButton: some View {
        Button {
            withAnimation(SharpitMotion.reveal) {
                scrollPosition.scrollTo(id: CoachThreadLayout.endId, anchor: .bottom)
            }
        } label: {
            Image(systemName: "arrow.down")
                .font(SharpitTypography.label.weight(.semibold))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 30, height: 30)
                .sharpitGlassCircle()
                .contentShape(Circle())
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel("Aller à la fin de la réponse")
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    #if DEBUG
    private func askDemoQuestions() async {
        for question in demoQuestions {
            try? await Task.sleep(for: .seconds(1.5))
            store.draft = question
            risesOnSend = true
            await store.send()
        }
    }
    #endif

    private var composerAction: CoachComposerAction {
        CoachComposerAction(isReplying: store.isReplying, isDictating: dictation.isListening, draft: store.draft)
    }

    /// The composer's one round button: the microphone on an empty field, send once there are
    /// words, stop while listening. The symbol morphs from one to the other.
    private var composerButton: some View {
        let action = composerAction
        return Button { perform(action) } label: {
            Image(systemName: action.symbol)
                .font(SharpitTypography.bodyEmphasis)
                // Untinted glass is light: the symbol goes muted there, not white.
                .foregroundStyle(action.isProminent ? SharpitColor.primaryForeground : SharpitColor.mutedForeground)
                .symbolEffect(.variableColor.iterative, isActive: action == .stopDictation)
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                .sharpitGlassControl(
                    in: Circle(),
                    tint: action.isProminent ? SharpitColor.primary : nil,
                    fallback: SharpitColor.radialTrack
                )
        }
        .buttonStyle(.plain)
        .disabled(action == .waiting)
        .accessibilityLabel(action.accessibilityLabel)
        .animation(SharpitMotion.selection, value: action)
    }

    private func perform(_ action: CoachComposerAction) {
        switch action {
        case .dictate:
            let store = store
            Task {
                await dictation.start(typed: store.draft) { text in store.draft = text }
            }
        case .stopDictation:
            dictation.stop()
        case .send:
            submit()
        case .waiting:
            break
        }
    }

    /// Return and the send button do the same thing: put the keyboard away, and send when
    /// there is something to send. Lowering it on an empty field is deliberate — the
    /// athlete asked to stop writing, and the thread is what they want to see.
    private func submit() {
        dictation.stop()
        composerIsFocused = false
        guard store.canSend else { return }
        risesOnSend = true
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
    /// Nil while an answer streams: a proposal cannot be answered mid-turn.
    let onAnswer: ((String, Bool) -> Void)?

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
                ForEach(CoachSegment.segments(of: message)) { segment in
                    switch segment {
                    case .text(_, let text):
                        // The coach writes markdown; rendering it as literal asterisks would be
                        // the app failing to read its own answer.
                        SharpitMarkdownText(markdown: text)
                            .textSelection(.enabled)
                    case .proposal(let proposal):
                        CoachProposalCard(proposal: proposal, onAnswer: answer(for: proposal))
                    }
                }
                if isStreaming {
                    CoachWritingMark()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension CoachMessageRow {
    private func answer(for proposal: CoachProposal) -> ((Bool) -> Void)? {
        guard case .awaiting(let approvalId) = proposal.status, let onAnswer else { return nil }
        return { approved in onAnswer(approvalId, approved) }
    }
}

/// A coach turn read in order: its prose, and its proposals where the coach made them.
/// Consecutive text parts read as one; reasoning, steps and read-only tools are not shown.
nonisolated enum CoachSegment: Identifiable, Equatable {
    case text(id: String, String)
    case proposal(CoachProposal)

    var id: String {
        switch self {
        case .text(let id, _): id
        case .proposal(let proposal): "proposal-\(proposal.id)"
        }
    }

    static func segments(of message: CoachMessage) -> [CoachSegment] {
        guard let parts = message.parts else {
            return message.text.isEmpty ? [] : [.text(id: "text-0", message.text)]
        }
        var segments: [CoachSegment] = []
        var pending: [String] = []
        func flush() {
            guard !pending.isEmpty else { return }
            segments.append(.text(id: "text-\(segments.count)", pending.joined(separator: "\n\n")))
            pending = []
        }
        for part in parts {
            if part["type"]?.string == "text", let text = part["text"]?.string, !text.isEmpty {
                pending.append(text)
            } else if let proposal = CoachProposal(part: part) {
                flush()
                segments.append(.proposal(proposal))
            }
        }
        flush()
        return segments
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

/// How the coach thread is laid out: the turns before, and the one under way — from the last
/// question on — which fills the screen so the question can rise to its top.
struct CoachThreadLayout {
    let earlier: [CoachMessage]
    let current: [CoachMessage]

    init(messages: [CoachMessage]) {
        guard let lastQuestion = messages.lastIndex(where: { $0.role == .user }) else {
            earlier = messages
            current = []
            return
        }
        earlier = Array(messages[..<lastQuestion])
        current = Array(messages[lastQuestion...])
    }

    /// The id of the turn under way, from its question's: the container a sent question rises with.
    static func turnId(_ questionId: String?) -> String {
        "turn-\(questionId ?? "none")"
    }

    /// The id of the thread's last line, which the arrow down scrolls to.
    static let endId = "thread-end"

    /// Past this many points below the screen, the answer has run out of sight.
    static let jumpThreshold: CGFloat = 24

    /// Whether the arrow down shows: the thread goes on below what the screen shows.
    static func showsJumpToLatest(contentHeight: CGFloat, visibleBottom: CGFloat) -> Bool {
        contentHeight - visibleBottom > jumpThreshold
    }
}

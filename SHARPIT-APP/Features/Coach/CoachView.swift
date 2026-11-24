import SwiftUI
import UIKit

/// The coach conversation.
///
/// A thread and a composer — the shape every chat has, because the athlete already knows
/// how to read it. What is not borrowed from a generic chat: no avatars, no typing dots
/// pretending to be a person, no sparkle chrome. The coach is an instrument that answers
/// in prose, and the design law keeps chatbot decoration off product surfaces. While it works,
/// one line says what it is doing (`CoachActivityLine`), read from the stream; its words then
/// come up in a fade (`sharpitStreamFade`) rather than being typed.
struct CoachView: View {
    @Environment(ShellRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: CoachStore
    @State private var showingHistory = false
    /// What the coach keeps about the athlete — free context, trips, constraints — moved here
    /// from Moi, beside the conversation that reads it.
    @State private var showingMemory = false
    /// The coach budget in full — the composer's gauge only shows past half.
    @State private var showingUsage = false
    @FocusState private var composerIsFocused: Bool
    @State private var showsJumpToLatest = false
    /// The quota card, closed by the athlete; it comes back with the next question typed.
    @State private var showsQuickActions = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @State private var dictation = CoachDictation()
    /// Set by a send, so only a question just asked rises to the top.
    @State private var risesOnSend = false
    /// False while the page opens: what the composer learns then — the budget read, a subject
    /// brought from another screen — is simply there, never animated in (the athlete's remark,
    /// 2026-11-22: the field and the card over it moving on arrival read as ugly).
    @State private var composerIsSettled = false
    /// The first moments on screen, while the composer is laid out: nothing moves then.
    @State private var hasOpened = false

    private let conversations: any CoachConversationServing
    private let tokenProvider: (() async throws -> String)?
    #if DEBUG
    /// Questions asked by themselves, one after the other — the simulator demo only.
    var demoQuestions: [String] = []
    var demoOpensQuickActions = false
    #endif

    init(
        client: any CoachChatServing,
        conversations: any CoachConversationServing,
        quota: (any CoachQuotaServing)? = nil,
        tokenProvider: (() async throws -> String)?
    ) {
        self.conversations = conversations
        self.tokenProvider = tokenProvider
        _store = State(
            initialValue: CoachStore(
                client: client,
                conversations: conversations,
                quota: quota,
                tokenProvider: tokenProvider
            )
        )
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                thread
                if showsJumpToLatest, !showsQuickActions, !store.isEmpty {
                    jumpToLatestButton
                        .padding(.bottom, SharpitSpacing.sm)
                }
            }
                // A bar rather than a stacked row: the system then knows the composer is
                // chrome and keeps the tab bar below it instead of over it.
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
                .onDisappear { dictation.stop() }
                // The thread reads on one sheet under the coach's wash.
                .cliniqueSheet(wash: .coach)
                #if DEBUG
                .task { await askDemoQuestions() }
                #endif
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(LiquidNavChrome())
            .toolbar {
                ToolbarItem(placement: .principal) { Text("") }
                SharpitBarTitle(String(localized: "Coach"))
                // A new conversation first, the list of actions after it, on the right as everywhere.
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
                SharpitBarGap()
                // The list of actions — conversations, memory, usage — on the right, as everywhere.
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            composerIsFocused = false
                            showingHistory = true
                        } label: {
                            Label("Conversations", systemImage: "clock.arrow.circlepath")
                        }
                        Button {
                            composerIsFocused = false
                            showingMemory = true
                        } label: {
                            Label("Mémoire", systemImage: "brain.head.profile")
                        }
                        Button {
                            composerIsFocused = false
                            showingUsage = true
                        } label: {
                            Label("Consommation", systemImage: "gauge.with.dots.needle.33percent")
                        }
                    } label: {
                        Label("Actions", systemImage: "ellipsis")
                    }
                    .disabled(tokenProvider == nil)
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
            .sheet(isPresented: $showingUsage) {
                CoachUsageSheet(quota: store.quota) {
                    showingUsage = false
                    router.openSettings(on: .pro)
                }
                .task { await store.refreshQuota(force: true) }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                CoachReplyLiveActivityController.shared.startIfNeeded(
                    conversationId: store.conversationId ?? "",
                    isReplying: store.isReplying
                )
            }
        }
        .task {
            await store.refreshQuota()
            // After the frame that drew what was read, so that frame is not animated either.
            try? await Task.sleep(for: .milliseconds(300))
            composerIsSettled = true
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            hasOpened = true
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
                                .foregroundStyle(SharpitColor.statusWatchForeground)
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
        // The Coach tab tapped again: the system scrolls to the top, the thread goes to its latest.
        .onChange(of: router.coachReselectTick) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(SharpitMotion.reveal) {
                    scrollPosition.scrollTo(id: CoachThreadLayout.endId, anchor: .bottom)
                }
            }
        }
        // History open and post-interrupt resync: jump to the latest turn. `initialOffset`
        // alone never fires again once the ScrollView has already laid out empty.
        .onChange(of: store.endAnchorRevision) { _, _ in
            guard !store.isEmpty else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(SharpitMotion.reveal) {
                    scrollPosition.scrollTo(id: CoachThreadLayout.endId, anchor: .bottom)
                }
            }
        }
    }

    private func messageRow(_ message: CoachMessage) -> some View {
        CoachMessageRow(
            message: message,
            isStreaming: isStreaming(message),
            isReplying: store.isReplying,
            onAnswer: answerHandler,
            onRetry: retryHandler,
            onOpenNutrition: { router.openToday(.nutrition) },
            onOpenPlan: { router.openPlan(on: $0) },
            onFollowUp: followUpHandler(for: message)
        )
        .id(message.id)
    }

    /// A suggestion under the last answer, sent as the athlete's question — not while a reply runs
    /// or a proposal waits, since a new question would refuse it.
    private func followUpHandler(for message: CoachMessage) -> ((String) -> Void)? {
        guard message.id == store.messages.last?.id, !store.isReplying, !store.hasPendingApproval else { return nil }
        return { question in
            dictation.stop()
            composerIsFocused = false
            store.draft = question
            risesOnSend = true
            Task { await store.send() }
        }
    }

    /// Answers a proposal card. Always available — `respond` stops an in-flight stream first,
    /// so Ajouter stays tappable while the SSE is still closing.
    private var answerHandler: ((String, Bool, JSONValue?, String?) -> Void)? {
        let store = store
        return { approvalId, approved, input, reason in
            Task {
                await store.respond(
                    to: approvalId,
                    approved: approved,
                    replacingInput: input,
                    reasonOverride: reason
                )
            }
        }
    }

    /// Re-sends a failed food-log (or other) approval after clearing its fingerprint.
    private var retryHandler: ((String, JSONValue?) -> Void)? {
        let store = store
        return { approvalId, input in
            Task { await store.retry(approvalId: approvalId, replacingInput: input) }
        }
    }

    /// The last assistant turn, while it is still filling in.
    private func isStreaming(_ message: CoachMessage) -> Bool {
        store.isReplying && message.role == .assistant && message.id == store.messages.last?.id
    }

    /// What is left of the coach budget, once half of it is spent: an information card over the
    /// composer — its own surface, so it never reads through the thread — with a thin bar of
    /// what remains, « Passer Pro » for a Free athlete, and a close that holds until the next
    /// keystroke, since the budget matters again the moment a question is being written.
    /// The budget, said quietly under the field: a short gauge and one line, in the watch ink
    /// once it is spent. No card, no cross: it takes a line, not the composer's place.
    private func quotaLine(_ quota: V1CoachQuota, line: String) -> some View {
        let spent = quota.retryAfterSeconds != nil
        return HStack(spacing: SharpitSpacing.xs) {
            ProgressView(value: 1 - quota.usedRatio)
                .tint(spent ? SharpitColor.statusWatchMark : SharpitColor.foreground)
                .frame(width: 36)
                .accessibilityHidden(true)
            Text(line)
                .font(SharpitTypography.meta)
                .foregroundStyle(spent ? SharpitColor.statusWatchForeground : SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if CoachQuotaReadout.offersPro(quota) {
                Button("Passer Pro") { router.openSettings(on: .pro) }
                    .font(SharpitTypography.meta.weight(.semibold))
                    .foregroundStyle(SharpitColor.foreground)
                    .buttonStyle(.sharpitPressable)
            }
        }
        .padding(.horizontal, SharpitSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }

    /// The composer's one height — the smallest tappable size, for the field and both circles.
    private static let controlHeight = SharpitSpacing.minimumTouchTarget

    @ViewBuilder
    private var composer: some View {
        if store.needsPro {
            SharpitProTeaser(
                title: String(localized: "Coach"),
                message: String(localized: "Pose tes questions au coach qui connaît tes données, avec SharpIt Pro. Tes séances et ta santé restent ouvertes sans abonnement.")
            )
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, SharpitSpacing.sm)
        } else {
            questionComposer
        }
    }

    /// Only while nothing is said or being said: an empty thread, an empty field, nothing joined.
    private var showsSuggestions: Bool {
        store.isEmpty && store.draft.isEmpty && store.pendingContext == nil && !dictation.isListening
    }

    private var showsQuotaNotice: Bool {
        store.quota.flatMap { CoachQuotaReadout.line($0) } != nil
    }

    /// The field opens into two floors — the words over the whole width, the controls on a row
    /// under them — as soon as it is written in, carries a subject or listens. At rest it is one line.
    private var composerIsExpanded: Bool {
        composerIsFocused || dictation.isListening || store.pendingContext != nil
            || store.draft.count > 26 || store.draft.contains("\n")
    }

    private var questionComposer: some View {
        VStack(spacing: SharpitSpacing.xs) {
            if let failure = dictation.failure {
                Text(failure)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.statusWatchForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showsSuggestions {
                // An empty thread stays bare: three ways in, low, where the thumb is. No rules, no card.
                CoachQuickActionList(actions: CoachQuickAction.suggested, showsDividers: false, onPick: start, inset: SharpitSpacing.xs)
                    .transition(.opacity)
            }
            // Against the box, so the card grows out of its « + ».
            if showsQuickActions, !dictation.isListening {
                quickActionsPanel
            }

            SharpitGlassGroup { composerBox }

            if showsQuotaNotice, let quota = store.quota, let line = CoachQuotaReadout.line(quota) {
                quotaLine(quota, line: line)
            }
        }
        .padding(.horizontal, SharpitSpacing.pageInset)
        .padding(.top, SharpitSpacing.xs)
        .padding(.bottom, SharpitSpacing.sm)
        .animation(SharpitMotion.reveal, value: composerIsExpanded)
        .animation(SharpitMotion.fade, value: showsSuggestions)
        .animation(SharpitMotion.reveal, value: dictation.isListening)
        // The budget line fades in when an answer takes the budget past half — never as the
        // page opens, and a subject is animated only by the tap that sets or drops it.
        .animation(composerIsSettled ? SharpitMotion.fade : nil, value: showsQuotaNotice)
        .transaction { transaction in
            guard !hasOpened else { return }
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .onChange(of: store.draft) { _, draft in
            if !draft.isEmpty, showsQuickActions { SharpitMotion.run(SharpitMotion.selection) { showsQuickActions = false } }
        }
    }

    /// One glass box. The field is one view whatever the floor it is on — only its insets move —
    /// so opening the box never drops the keyboard; the controls sit on its bottom corners.
    private var composerBox: some View {
        let expanded = composerIsExpanded
        return VStack(alignment: .leading, spacing: 0) {
            if let context = store.pendingContext {
                // Inside the box: the subject leaves with the question.
                CoachContextTag(context: context, isInline: true) {
                    SharpitMotion.run { store.dropContext() }
                }
                .padding(.leading, SharpitSpacing.xs)
                .padding(.top, SharpitSpacing.xxs)
                .transition(.opacity)
            }

            TextField(
                store.hasPendingApproval
                    ? String(localized: "Réponds à la proposition, ou écris pour l'ignorer")
                    : store.pendingContext?.prompt ?? String(localized: "Écris au coach"),
                text: $store.draft,
                axis: .vertical
            )
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(1...6)
                .focused($composerIsFocused)
                // Return at end of a clean line = send. Paste with newlines stays editable.
                .onChange(of: store.draft) { old, new in
                    guard new.contains("\n") else { return }
                    if CoachComposerDraft.shouldSendOnNewline(old: old, new: new) {
                        store.draft = String(new.dropLast())
                        submit()
                    }
                }
                .padding(.vertical, SharpitSpacing.xs + 2)
                .frame(minHeight: Self.controlHeight)
                .padding(.horizontal, expanded ? SharpitSpacing.sm : Self.controlHeight)
                .padding(.bottom, expanded ? Self.controlHeight : 0)
                .animation(SharpitMotion.selection, value: store.draft.count / 40)
                .submitLabel(.send)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottomLeading) {
            if dictation.isListening { listeningMark } else { quickActionsButton }
        }
        .overlay(alignment: .bottomTrailing) { composerButton }
        .padding(6)
        .sharpitGlassControl(
            in: RoundedRectangle(cornerRadius: 28, style: .continuous),
            fallback: SharpitColor.tile
        )
        // The box in hand is told by its edge.
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(SharpitColor.foreground.opacity(composerIsFocused ? 0.22 : 0), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }

    /// « + », opposite the ink button: starting points that tag the conversation and open
    /// the question, for the asks the coach answers best (adjusting a session or the week).
    private var quickActionsButton: some View {
        Button {
            SharpitMotion.run(SharpitMotion.selection) { showsQuickActions.toggle() }
        } label: {
            Image(systemName: "plus")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(showsQuickActions ? SharpitColor.foreground : SharpitColor.slate)
                .rotationEffect(.degrees(showsQuickActions ? 45 : 0))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .disabled(store.isReplying)
        .accessibilityLabel(showsQuickActions ? "Fermer les demandes" : "Démarrer une demande")
        .transition(.opacity)
    }

    /// While the coach listens the « + » gives its corner to the wave; the words land in the field.
    private var listeningMark: some View {
        HStack(spacing: SharpitSpacing.xs) {
            Image(systemName: "waveform")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text("Écoute…")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
        }
        .padding(.leading, SharpitSpacing.sm)
        .frame(height: Self.controlHeight)
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dictée en cours")
    }

    /// The starting points as one card over the box, growing from the « + »; a pick closes it.
    private var quickActionsPanel: some View {
        // Capped and scrolled: at the largest text the five choices ran past the top of the screen.
        Group {
            if typeSize.isAccessibilitySize {
                ScrollView { CoachQuickActionList(actions: panelActions, onPick: start) }
                    .frame(height: 320)
            } else {
                CoachQuickActionList(actions: panelActions, onPick: start)
            }
        }
        .padding(.vertical, SharpitSpacing.xxs)
        // Opaque: glass let the thread's text show through the choices.
        .background(SharpitColor.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(SharpitColor.outline, lineWidth: 1)
        }
        .sharpitShadow(.control)
        // Grows a little out of the « + », leaves by fading: faster out than in, never sucked back.
        .transition(.asymmetric(
            insertion: .scale(scale: 0.96, anchor: .bottomLeading).combined(with: .opacity),
            removal: .opacity
        ))
    }

    /// On an empty thread the three suggestions stay above the box: the « + » adds the others only.
    private var panelActions: [CoachQuickAction] {
        CoachQuickAction.panel(showingSuggestions: store.isEmpty && store.draft.isEmpty && store.pendingContext == nil)
    }

    private func start(_ action: CoachQuickAction) {
        SharpitMotion.run(SharpitMotion.selection) {
            store.attach(action.context(trainingDayId: TrainingDayId.today()))
            showsQuickActions = false
        }
        composerIsFocused = true
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
        if demoOpensQuickActions {
            try? await Task.sleep(for: .seconds(1))
            SharpitMotion.run(SharpitMotion.selection) { showsQuickActions = true }
            return
        }
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

    /// The box's one trailing control: the microphone while the field is empty — a plain glyph —
    /// then the ink button, send once there are words, stop while listening or while the coach
    /// answers. The ink arrives under the glyph; the symbol morphs from one to the other.
    private var composerButton: some View {
        let action = composerAction
        let isInk = action != .dictate
        let waits = action == .send && store.isOutOfQuota
        return Button { perform(action) } label: {
            Image(systemName: action == .dictate || action == .send ? action.symbol : "stop.fill")
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(isInk ? SharpitColor.primaryForeground : SharpitColor.slate)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer)))
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .background {
                    Circle()
                        .fill(SharpitColor.primary)
                        .scaleEffect(isInk ? 1 : 0.6)
                        .opacity(isInk ? 1 : 0)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        // A spent budget: the button waits.
        .disabled(waits)
        .opacity(waits ? 0.35 : 1)
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
            store.stopReply()
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
///
/// Copy: each turn is one selectable block prefixed with « Moi » / « Coach » so a drag can
/// cross messages as one text. Long-press copies the labeled turn (not one markdown fragment).
/// Proposal / food cards stay outside the selection path — a menu over them stole field taps.
private struct CoachMessageRow: View {
    let message: CoachMessage
    let isStreaming: Bool
    let isReplying: Bool
    let onAnswer: ((String, Bool, JSONValue?, String?) -> Void)?
    let onRetry: ((String, JSONValue?) -> Void)?
    let onOpenNutrition: (() -> Void)?
    var onOpenPlan: ((Date) -> Void)? = nil
    /// Nil unless this is the thread's last answer, settled: older suggestions are spent.
    var onFollowUp: ((String) -> Void)? = nil

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: SharpitSpacing.xxs) {
                if let context = message.context {
                    CoachContextTag(context: context)
                }
                // A question is copied whole, on a long press: no selection handles on one's own words.
                // The mock-up's bubble: ink, its corner toward the speaker tightened.
                Text(message.text)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .lineSpacing(3)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(
                        SharpitColor.inkSurface,
                        in: UnevenRoundedRectangle(
                            topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20,
                            style: .continuous
                        )
                    )
                    .frame(maxWidth: 280, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .coachCopyMenu(CoachMessageCopy.plainText(of: message))

        case .assistant:
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                ForEach(CoachSegment.segments(of: message)) { segment in
                    switch segment {
                    case .text(_, let text):
                        // One Text (AttributedString) so a selection can take any part of it;
                        // no context menu here, it would take the long press from the selection.
                        coachProse(text)
                    case .proposal(let proposal):
                        CoachProposalCard(proposal: proposal, onAnswer: answer(for: proposal), onOpenPlan: onOpenPlan)
                            .sharpitStreamArrival(isStreaming: isStreaming)
                    case .foodLog(let proposal):
                        CoachFoodLogCard(
                            proposal: proposal,
                            onAnswer: answer(for: proposal),
                            onRetry: retry(for: proposal),
                            onOpenNutrition: onOpenNutrition,
                            isReplying: isReplying
                        )
                        .sharpitStreamArrival(isStreaming: isStreaming)
                    case .workout(_, let workout):
                        CoachWorkoutCard(workout: workout, onAdd: addToPlan(workout))
                            .sharpitStreamArrival(isStreaming: isStreaming)
                    case .dataCard(_, let card):
                        CoachDataCardView(card: card)
                    case .followUps(_, let suggestions):
                        if let onFollowUp {
                            CoachFollowUpsView(suggestions: suggestions, onSelect: onFollowUp)
                                .sharpitStreamArrival(isStreaming: isStreaming)
                        }
                    }
                }
                if isStreaming {
                    // What the coach is doing while no words come; gone once they do.
                    if let activity = CoachActivity.current(parts: message.parts ?? []) {
                        CoachActivityLine(activity: activity)
                            .transition(.opacity)
                    }
                } else if !CoachMessageCopy.plainText(of: message).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    CoachCopyButton(text: CoachMessageCopy.plainText(of: message))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(SharpitMotion.fade, value: isStreaming ? CoachActivity.current(parts: message.parts ?? []) == nil : true)
        }
    }

    /// « Ajouter au plan » on a session the coach drew: asked as the athlete's own question, so
    /// the coach answers with a proposal. Only on the thread's last answer, as the follow-ups.
    private func addToPlan(_ workout: CoachWorkout) -> (() -> Void)? {
        guard let onFollowUp else { return nil }
        return { onFollowUp(String(localized: "Ajoute « \(workout.title) » à mon plan.")) }
    }

    private func coachProse(_ markdown: String) -> some View {
        SharpitMarkdownText(markdown: markdown, isStreaming: isStreaming)
    }
}

/// Copies a whole reply: a quiet glyph at its end that turns into a check for a moment, so the
/// tap is confirmed where it was made, then settles back.
private struct CoachCopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            withAnimation(SharpitMotion.selection) { copied = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.6))
                withAnimation(SharpitMotion.selection) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(copied ? SharpitColor.foreground : SharpitColor.slate)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: SharpitSpacing.minimumTouchTarget, height: SharpitSpacing.minimumTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, -SharpitSpacing.xs)
        .accessibilityLabel(copied ? String(localized: "Copié") : String(localized: "Copier la réponse"))
    }
}

/// Text put on the pasteboard — labeled turns so a paste reads as a conversation.
enum CoachMessageCopy {
    static func plainText(of message: CoachMessage) -> String {
        let assembled = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !assembled.isEmpty { return message.text }
        return CoachSegment.segments(of: message).compactMap { segment -> String? in
            if case .text(_, let text) = segment {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : text
            }
            return nil
        }.joined(separator: "\n\n")
    }

    static func roleLabel(for message: CoachMessage) -> String {
        message.role == .user ? String(localized: "Moi") : String(localized: "Coach")
    }

    /// « Coach\n… » / « Moi\n… » — what selection and long-press put on the pasteboard.
    static func labeledTurn(_ message: CoachMessage) -> String {
        let body = plainText(of: message).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "" }
        return "\(roleLabel(for: message))\n\(body)"
    }

    static func labeledTranscript(messages: [CoachMessage]) -> String {
        messages.compactMap { turn -> String? in
            let labeled = labeledTurn(turn)
            return labeled.isEmpty ? nil : labeled
        }.joined(separator: "\n\n")
    }

}

private extension View {
    @ViewBuilder
    func coachCopyMenu(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            self
        } else {
            contextMenu {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copier", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

extension CoachMessageRow {
    private func answer(for proposal: CoachProposal) -> ((Bool, String?) -> Void)? {
        guard case .awaiting(let approvalId) = proposal.status, let onAnswer else { return nil }
        return { approved, reason in onAnswer(approvalId, approved, nil, reason) }
    }

    private func answer(for proposal: CoachFoodLogProposal) -> ((Bool, JSONValue?) -> Void)? {
        guard case .awaiting = proposal.status, let onAnswer else { return nil }
        let approvalId = proposal.approvalId
        return { approved, input in onAnswer(approvalId, approved, input, nil) }
    }

    private func retry(for proposal: CoachFoodLogProposal) -> ((JSONValue?) -> Void)? {
        guard case .failed = proposal.status, let onRetry else { return nil }
        let approvalId = proposal.approvalId
        return { input in onRetry(approvalId, input) }
    }
}

/// A coach turn read in order: its prose, its proposals and its cards where the coach made them.
/// Consecutive text parts read as one; reasoning, steps and read-only tools are not shown.
nonisolated enum CoachSegment: Identifiable, Equatable {
    case text(id: String, String)
    case proposal(CoachProposal)
    case foodLog(CoachFoodLogProposal)
    case workout(id: String, CoachWorkout)
    case followUps(id: String, [String])
    case dataCard(id: String, CoachDataCard)

    var id: String {
        switch self {
        case .text(let id, _): id
        case .proposal(let proposal): "proposal-\(proposal.id)"
        case .foodLog(let proposal): "food-\(proposal.id)"
        case .workout(let id, _): "workout-\(id)"
        case .followUps(let id, _): "follow-ups-\(id)"
        case .dataCard(let id, _): "data-card-\(id)"
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
            } else if let food = CoachFoodLogProposal(part: part) {
                flush()
                segments.append(.foodLog(food))
            } else if let proposal = CoachProposal(part: part) {
                flush()
                segments.append(.proposal(proposal))
            } else if let workout = CoachWorkout(part: part) {
                flush()
                segments.append(.workout(id: part["toolCallId"]?.string ?? "\(segments.count)", workout))
            } else if let card = CoachDataCard(part: part) {
                flush()
                segments.append(.dataCard(id: part["toolCallId"]?.string ?? "\(segments.count)", card))
            } else if let followUps = CoachFollowUps(part: part) {
                flush()
                segments.append(.followUps(id: part["toolCallId"]?.string ?? "\(segments.count)", followUps.suggestions))
            }
        }
        flush()
        return segments
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
                String(localized: """
                Une séance, ta semaine, un signal du jour. \
                Depuis un écran, le bouton « discuter » joint le sujet à ta question.
                """)
            )
            .font(SharpitTypography.body)
            .foregroundStyle(SharpitColor.slate)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The coach's starting points as lines: split by hairlines in the « + » card, bare above the
/// box of an empty thread.
struct CoachQuickActionList: View {
    var actions: [CoachQuickAction] = CoachQuickAction.allCases
    var showsDividers = true
    let onPick: (CoachQuickAction) -> Void
    var inset: CGFloat = SharpitSpacing.md

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element) { index, action in
                if showsDividers, index > 0 { CliniqueDivider().padding(.leading, inset + 34) }
                Button { onPick(action) } label: {
                    HStack(spacing: SharpitSpacing.sm) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(SharpitColor.slate)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        Text(action.label)
                            .font(SharpitTypography.body)
                            .foregroundStyle(SharpitColor.foreground)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, inset)
                    .frame(maxWidth: .infinity, minHeight: SharpitSpacing.minimumTouchTarget + 4, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
            }
        }
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

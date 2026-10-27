import SwiftUI

/// A prescription, as any screen can describe it.
///
/// Plan holds a `V1PlannedSessionItem`; Today holds a `SessionCardModel` projected for
/// display. Both open the same drawer, so both map into this rather than the drawer
/// growing a second initialiser — or, worse, Today growing a second drawer.
struct PlannedSessionPreview: Identifiable, Hashable {
    /// Addresses the prescription itself. Absent when the surface only knows a display
    /// line (a brick's group, say), which is why the coach button is conditional.
    let sessionId: String?
    let title: String
    let sport: String
    let symbolName: String
    let date: Date?
    let metrics: [PlannedSessionMetric]
    /// The prescribed length, kept as a number beside its metric: a brick adds its legs up.
    let durationMin: Int?
    let notes: String?
    /// Why the coach wrote it — Decision Memory rationale when the session was accepted.
    let rationale: String?
    /// What to actually do. Empty when the surface has no structure to show.
    let steps: [V1PlannedSessionStep]
    /// True when the breakdown was inferred from duration and intensity rather than
    /// written — worth saying, because the athlete did not choose it.
    let stepsAreDerived: Bool
    /// Warm-up and stretches (SHARPIT ADR-114) from the breakdown, when the surface has it.
    let routines: V1SessionRoutines?
    /// STRENGTH / mobilité prescription — drives « Lancer la séance ».
    let strengthPrescription: JSONValue?

    /// One of the week's key sessions (SHARPIT F2).
    let isKey: Bool

    var id: String { sessionId ?? title }

    /// True when the prescription has at least one named exercise to follow on the phone.
    var canFollowOnPhone: Bool {
        StrengthExerciseDraft.exercises(in: strengthPrescription).contains(where: \.isNamed)
    }

    init(
        sessionId: String?,
        title: String,
        sport: String,
        symbolName: String,
        date: Date?,
        metrics: [PlannedSessionMetric],
        durationMin: Int? = nil,
        notes: String?,
        rationale: String? = nil,
        steps: [V1PlannedSessionStep],
        stepsAreDerived: Bool,
        routines: V1SessionRoutines? = nil,
        strengthPrescription: JSONValue? = nil,
        isKey: Bool = false
    ) {
        self.routines = routines
        self.isKey = isKey
        self.sessionId = sessionId
        self.title = title
        self.sport = sport
        self.symbolName = symbolName
        self.date = date
        self.metrics = metrics
        self.durationMin = durationMin
        self.notes = notes
        self.rationale = rationale
        self.steps = steps
        self.stepsAreDerived = stepsAreDerived
        self.strengthPrescription = strengthPrescription
    }
}

/// What a screen hands the drawer so the athlete can edit, move or delete the session.
struct SessionEditingContext {
    let session: V1PlannedSessionItem
    let editor: PlanEditor
    /// The session as it now reads, for the drawer to show.
    let onSaved: (V1PlannedSessionItem) -> Void
    /// The session is gone; the drawer closes.
    let onDeleted: () -> Void
}

struct PlannedSessionMetric: Hashable {
    let label: String
    let value: String
}

extension PlannedSessionPreview {
    /// `isExpertReading` is passed rather than read from the environment: a preview is built
    /// outside any view, by the screen that owns the sheet.
    init(session: V1PlannedSessionItem, isExpertReading: Bool = false) {
        var metrics: [PlannedSessionMetric] = []
        if let durationMin = session.durationMin {
            metrics.append(PlannedSessionMetric(label: String(localized: "Durée"), value: "\(durationMin) min"))
        }
        if let intensity = session.intensity, !intensity.isEmpty {
            metrics.append(PlannedSessionMetric(label: String(localized: "Intensité"), value: intensity.capitalized))
        }
        // What the session is expected to cost. Shown in both readings, named for the one it
        // is read in (ADR 0006, reversing the omission this comment used to record).
        if let load = session.load, load > 0 {
            metrics.append(PlannedSessionMetric(
                label: isExpertReading ? "TSS" : String(localized: "Charge"),
                value: "\(Int(load.rounded()))"
            ))
        }

        self.init(
            sessionId: session.id,
            title: session.title ?? session.displayType,
            sport: session.displayType,
            symbolName: session.symbolName,
            date: session.date,
            metrics: metrics,
            durationMin: session.durationMin,
            // The déroulé the athlete wrote is the instruction; `notes` is an older payload's.
            notes: session.description ?? session.notes,
            rationale: session.rationale,
            steps: session.breakdown?.steps ?? [],
            stepsAreDerived: session.breakdown?.derived ?? false,
            routines: session.breakdown?.routines,
            strengthPrescription: session.strengthPrescription,
            isKey: session.isKey
        )
    }

    /// Today's own line. Its metrics are already resolved for display, so they travel as
    /// they are rather than being recomputed from a shape Today does not have.
    /// The breakdown of `sessionId` among the sessions of a day, nil when it is not there
    /// or carries none.
    static func breakdown(
        of sessionId: String,
        in sessions: [V1PlannedSessionItem]
    ) -> V1PlannedSessionBreakdown? {
        guard let breakdown = sessions.first(where: { $0.id == sessionId })?.breakdown,
              !breakdown.steps.isEmpty else { return nil }
        return breakdown
    }

    /// A session the coach proposes and the athlete has not added yet: no id, so nothing to
    /// discuss, link or push — only what it holds and why.
    init(generated session: V1GeneratedSession, isExpertReading: Bool = false) {
        var metrics: [PlannedSessionMetric] = []
        if session.durationMin > 0 {
            metrics.append(PlannedSessionMetric(label: String(localized: "Durée"), value: "\(Int(session.durationMin)) min"))
        }
        metrics.append(PlannedSessionMetric(
            label: String(localized: "Intensité"),
            value: CoachProposal.intensityLabels[session.intensity] ?? session.intensity.capitalized
        ))
        if session.load > 0 {
            metrics.append(PlannedSessionMetric(
                label: isExpertReading ? "TSS" : String(localized: "Charge"),
                value: "\(Int(session.load.rounded()))"
            ))
        }
        self.init(
            sessionId: nil,
            title: session.title,
            sport: session.type.label,
            symbolName: session.type.symbolName,
            date: TrainingDayId.date(session.date),
            metrics: metrics,
            // The steps are the instruction: the coach writes no prose beside them any more.
            notes: nil,
            rationale: session.rationale,
            steps: session.breakdown?.steps ?? [],
            stepsAreDerived: session.breakdown?.derived ?? false,
            routines: session.breakdown?.routines,
            isKey: session.isKey
        )
    }

    init(card: SessionCardModel) {
        self.init(
            sessionId: card.plannedSessionId,
            title: card.title,
            sport: card.sport ?? String(localized: "Séance"),
            symbolName: SharpitSportTone.symbolName(for: card.sport ?? ""),
            date: nil,
            metrics: card.metrics.map {
                PlannedSessionMetric(
                    label: $0.label,
                    value: $0.unit.isEmpty ? $0.value : "\($0.value) \($0.unit)"
                )
            },
            notes: card.subtitle,
            rationale: card.rationale,
            // Today's payload carries the line and its exercises, not the steps behind it:
            // the breakdown arrives with the plan, so it is shown there.
            steps: [],
            stepsAreDerived: false,
            strengthPrescription: card.strengthPrescription,
            isKey: card.isKey
        )
    }
}

/// What a planned session holds, in a sheet.
///
/// A planned session has no detail screen to open — there is nothing recorded yet, only
/// an intention. A drawer says what is prescribed, lets the athlete ask the coach about it,
/// and docks the one action that readies it: the watch, or the phone's guided follow.
struct PlannedSessionDrawer: View {
    let preview: PlannedSessionPreview
    /// Nil where the screen cannot link, so the action is absent rather than dead.
    var linking: SessionLinkContext?
    /// Lets the athlete edit, move or delete the session; nil where the plan cannot be changed.
    var editing: SessionEditingContext?
    /// Sends the session to the Garmin watch; nil where Garmin is not linked or the sport waits.
    var watch: SessionWatchContext?
    /// Creates the STRENGTH activity after a phone-guided follow; nil where the screen cannot write.
    var guidedFinish: GuidedStrengthFinishContext?
    /// Fetches the session's breakdown when the preview arrived without one — Today's
    /// payload carries the line, not the prescription behind it.
    var loadBreakdown: (() async -> V1PlannedSessionBreakdown?)?
    /// Today's line has no prescription: load it with the plan day so « Lancer la séance » still appears.
    var loadStrengthPrescription: (() async -> JSONValue?)?
    /// The breakdown read last time this session was opened, shown at once while
    /// `loadBreakdown` asks again — the loader only spins on a first opening.
    var storedBreakdown: V1PlannedSessionBreakdown?
    /// Pushed inside another sheet's stack — a brick's leg — rather than presented: no
    /// stack, detents or close button of its own.
    var isEmbedded = false
    let onDiscussWithCoach: (CoachDiscussContext) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var showingLinkPicker = false
    @State private var loadedBreakdown: V1PlannedSessionBreakdown?
    @State private var isLoadingBreakdown = false
    @State private var loadedPrescription: JSONValue?
    @State private var guidedSession: GuidedStrengthSession?
    @State private var isEditing = false
    @State private var isConfirmingDeletion = false
    @Environment(ProStore.self) private var pro: ProStore?
    @State private var isSendingToWatch = false
    @State private var isConfirmingWatchResend = false
    @State private var isShowingProPaywall = false
    /// The day just sent, until the plan read again brings the server's copy.
    @State private var watchSentDay: String?
    @State private var isTitleInBar = false

    /// Roughly the sport line and the title: past it, the title is out of sight.
    private static let headerHeight: CGFloat = 96

    private var effectivePrescription: JSONValue? {
        preview.strengthPrescription ?? loadedPrescription
    }

    private var canFollowOnPhone: Bool {
        StrengthExerciseDraft.exercises(in: effectivePrescription).contains(where: \.isNamed)
    }

    private var steps: [V1PlannedSessionStep] {
        preview.steps.isEmpty ? loadedBreakdown?.steps ?? [] : preview.steps
    }

    /// What the athlete did with a routine can be said from the session's day on, where the
    /// plan can be written.
    private var routineStatusRecorder: ((V1RoutinePart, V1RoutineStatus?) -> Void)? {
        guard let editing,
              let day = preview.date,
              Calendar.current.startOfDay(for: day) <= Calendar.current.startOfDay(for: .now)
        else { return nil }
        return { part, status in editing.editor.markRoutine(part, of: editing.session, as: status) }
    }

    private var stepsAreDerived: Bool {
        preview.steps.isEmpty ? loadedBreakdown?.derived ?? false : preview.stepsAreDerived
    }

    var body: some View {
        if isEmbedded {
            page
        } else {
            NavigationStack {
                page
                    .navigationDestination(isPresented: $isEditing) {
                        if let editing {
                            PlannedSessionEditPage(session: editing.session, editor: editing.editor, onSaved: editing.onSaved)
                        }
                    }
                    .confirmationDialog(
                        String(localized: "Supprimer cette séance ?"),
                        isPresented: $isConfirmingDeletion,
                        titleVisibility: .visible
                    ) {
                        Button("Supprimer la séance", role: .destructive) {
                            guard let editing else { return }
                            editing.editor.delete(editing.session)
                            editing.onDeleted()
                        }
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("Elle disparaît de ton plan.")
                    }
            }
            .presentationDetents([.medium, .large])
            .sharpitSheet()
            .presentationDragIndicator(.visible)
        }
    }

    private var page: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                PlannedSessionSummary(
                    preview: preview,
                    steps: steps,
                    stepsAreDerived: stepsAreDerived,
                    isLoadingBreakdown: isLoadingBreakdown,
                    routines: preview.routines ?? loadedBreakdown?.routines,
                    onRoutineStatus: routineStatusRecorder
                ) {
                    // Without an id the coach cannot be told *which* session, and a tag
                    // naming the wrong one is worse than no tag.
                    if let sessionId = preview.sessionId {
                        CoachDiscussButton(title: String(localized: "Discuter de cette séance")) {
                            onDiscussWithCoach(
                                CoachDiscuss.describe(
                                    .plannedSession(sessionId: sessionId),
                                    name: preview.title
                                )
                            )
                            dismiss()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SharpitSpacing.pageInset)
        }
        .background(SharpitCanvasBackground())
        // The title moves to the bar once the header has scrolled away, as a large title does.
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > Self.headerHeight
        } action: { _, isPast in
            withAnimation(SharpitMotion.fade) { isTitleInBar = isPast }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let dockAction {
                SharpitActionDock { dockButton(dockAction) }
                    .transition(.opacity)
            }
        }
        .animation(SharpitMotion.reveal, value: steps.count)
        .animation(SharpitMotion.reveal, value: canFollowOnPhone)
        .task { await fetchBreakdownIfMissing() }
        .navigationTitle(isEmbedded ? preview.sport : (isTitleInBar ? preview.title : ""))
        .navigationBarTitleDisplayMode(.inline)
        // On the page, not the stack: a brick's leg, pushed in its brick's stack, keeps its « … ».
        .toolbar {
            if isSendingToWatch, dockAction != .watch {
                ToolbarItem(placement: .primaryAction) { ProgressView() }
            } else if !actionsMenu.isEmpty {
                ToolbarItem(placement: .primaryAction) { actionsMenu }
            }
        }
        .confirmationDialog(
            String(localized: "Renvoyer la séance ?"),
            isPresented: $isConfirmingWatchResend,
            titleVisibility: .visible
        ) {
            Button("Renvoyer") { Task { await sendToWatch(replace: true) } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La version déjà sur ta montre est remplacée.")
        }
        .sheet(isPresented: $isShowingProPaywall) {
            if let pro { SharpitProPaywallSheet(store: pro) }
        }
        .sheet(isPresented: $showingLinkPicker) {
            if let sessionId = preview.sessionId, let linking {
                SessionLinkPicker(sessionId: sessionId, context: linking) {
                    showingLinkPicker = false
                    linking.onLinked()
                }
            }
        }
        .fullScreenCover(item: $guidedSession) { guided in
            if let guidedFinish {
                GuidedStrengthWorkoutView(session: guided, finish: guidedFinish)
            }
        }
    }

    private var actionsMenu: SessionActionsMenu {
        SessionActionsMenu(
            editing: editing.map { editing in
                SessionMenuEditing(
                    session: editing.session,
                    onEdit: { isEditing = true },
                    onMove: { day in editing.onSaved(editing.editor.move(editing.session, to: day)) },
                    onDelete: { isConfirmingDeletion = true }
                )
            },
            // Docked under the page when it is the session's one action, in the menu otherwise.
            watch: dockAction == .watch ? nil : watch.map { _ in
                SessionMenuAction(title: watchState.menuTitle, symbolName: watchState.symbolName) {
                    requestWatchSend()
                }
            },
            // Linking needs to know *which* session, as the coach button does.
            onLink: preview.sessionId != nil && linking != nil ? { showingLinkPicker = true } : nil
        )
    }

    /// The one thing to do with the session before it happens, docked at the bottom: follow a
    /// strength session on the phone, or put an endurance one on the watch.
    private enum DockAction { case guided, watch }

    private var dockAction: DockAction? {
        if canFollowOnPhone, guidedFinish != nil { return .guided }
        return watch == nil ? nil : .watch
    }

    @ViewBuilder
    private func dockButton(_ action: DockAction) -> some View {
        switch action {
        case .guided:
            SharpitPrimaryButton(title: String(localized: "Lancer la séance"), trailingSymbol: "play.circle.fill") {
                guidedSession = GuidedStrengthSession.make(
                    title: preview.title,
                    plannedSessionId: preview.sessionId,
                    prescription: effectivePrescription
                )
            }
            .accessibilityHint("Ouvre le suivi guidé sur le téléphone")
        case .watch:
            // Once on the watch, a resend is the quieter offer.
            SharpitPrimaryButton(
                title: watchState.menuTitle,
                style: watchState == .sent ? .secondary : .primary,
                isBusy: isSendingToWatch
            ) {
                requestWatchSend()
            }
            .disabled(isSendingToWatch)
        }
    }

    private var watchState: WatchPushState {
        guard let session = watch?.session else { return .notSent }
        return WatchPushState.of(
            garminWorkoutId: watchSentDay == nil ? session.garminWorkoutId : "sent",
            scheduledDate: watchSentDay ?? session.garminWorkoutScheduledDate,
            sessionDate: session.date
        )
    }

    /// Pro-only: a Free athlete is shown the offer. A session on the watch asks first, a moved one
    /// is replaced at once — the watch holds the wrong day.
    private func requestWatchSend() {
        if let pro, !pro.isPro {
            isShowingProPaywall = true
        } else if watchState == .sent {
            isConfirmingWatchResend = true
        } else {
            Task { await sendToWatch(replace: watchState == .moved) }
        }
    }

    private func sendToWatch(replace: Bool) async {
        guard let watch, !isSendingToWatch else { return }
        isSendingToWatch = true
        defer { isSendingToWatch = false }
        let (receipt, message) = await watch.send(replace: replace)
        if let receipt { watchSentDay = receipt.scheduledDate }
        toastCenter?.show(
            message,
            symbol: receipt == nil ? "exclamationmark.triangle" : "checkmark.circle.fill",
            tone: receipt == nil ? .error : .success,
            autoDismissAfter: receipt == nil ? 5 : 4
        )
    }

    private func fetchBreakdownIfMissing() async {
        async let breakdown: Void = fetchBreakdown()
        async let prescription: Void = fetchPrescription()
        _ = await (breakdown, prescription)
    }

    private func fetchBreakdown() async {
        guard preview.steps.isEmpty, loadedBreakdown == nil, let loadBreakdown else { return }
        loadedBreakdown = storedBreakdown
        isLoadingBreakdown = storedBreakdown == nil
        // A failed read keeps the stored copy rather than blanking what is on screen.
        if let fresh = await loadBreakdown(), fresh != loadedBreakdown {
            withAnimation(SharpitMotion.reveal) { loadedBreakdown = fresh }
        }
        isLoadingBreakdown = false
    }

    private func fetchPrescription() async {
        guard preview.strengthPrescription == nil, loadedPrescription == nil, let loadStrengthPrescription else { return }
        if let fresh = await loadStrengthPrescription() {
            withAnimation(SharpitMotion.reveal) { loadedPrescription = fresh }
        }
    }
}

extension GuidedStrengthSession: Identifiable {
    var id: String { plannedSessionId ?? title }
}

/// The way to hand a subject to the coach. A tinted pill near the top of the screen: it
/// is found because of where it sits and the one accent it carries, not because of its
/// size (ADR 0003).
struct CoachDiscussButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
                Text(title)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(SharpitTypography.bodyEmphasis)
            .foregroundStyle(SharpitColor.primary)
            .padding(.horizontal, SharpitSpacing.sm)
            .padding(.vertical, SharpitSpacing.xs)
            .background(SharpitColor.primary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityHint("Ouvre le coach avec ce sujet")
    }
}

#Preview {
    VStack(spacing: SharpitSpacing.md) {
        CoachDiscussButton(title: String(localized: "Discuter de cette séance")) {}
        CoachDiscussButton(title: String(localized: "Discuter avec le coach")) {}
    }
    .padding()
    .background(SharpitCanvasBackground())
}

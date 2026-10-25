import SwiftUI

/// Résumé's planned-session drawer with the same « … » as Plan's: send to the watch, link,
/// edit, move, delete. Today's card carries a preview, not the session, so the session is read
/// from the plan for the day; until it is read (or without a token) the drawer shows what the
/// card knew, with whatever actions need no session.
struct TodayPlannedSessionSheet: View {
    let preview: PlannedSessionPreview
    let day: Date
    let tokenProvider: (() async throws -> String)?
    let linking: SessionLinkContext?
    let guidedFinish: GuidedStrengthFinishContext?
    let loadBreakdown: (() async -> V1PlannedSessionBreakdown?)?
    let loadStrengthPrescription: (() async -> JSONValue?)?
    let storedBreakdown: V1PlannedSessionBreakdown?
    let onDiscuss: (CoachDiscussContext) -> Void

    @Environment(ShellRouter.self) private var router
    @Environment(\.isExpertReading) private var isExpertReading
    @Environment(\.dismiss) private var dismiss
    @State private var session: V1PlannedSessionItem?
    @State private var isGarminLinked = false
    /// Edits go through the same editor as Plan's; its store is only the writes' echo, since
    /// Résumé reads the day again from the router's calendar revision.
    @State private var editor: PlanEditor?

    init(
        preview: PlannedSessionPreview,
        day: Date,
        tokenProvider: (() async throws -> String)?,
        linking: SessionLinkContext?,
        guidedFinish: GuidedStrengthFinishContext?,
        loadBreakdown: (() async -> V1PlannedSessionBreakdown?)?,
        loadStrengthPrescription: (() async -> JSONValue?)?,
        storedBreakdown: V1PlannedSessionBreakdown?,
        onDiscuss: @escaping (CoachDiscussContext) -> Void
    ) {
        self.preview = preview
        self.day = day
        self.tokenProvider = tokenProvider
        self.linking = linking
        self.guidedFinish = guidedFinish
        self.loadBreakdown = loadBreakdown
        self.loadStrengthPrescription = loadStrengthPrescription
        self.storedBreakdown = storedBreakdown
        self.onDiscuss = onDiscuss
    }

    var body: some View {
        PlannedSessionDrawer(
            preview: session.map { PlannedSessionPreview(session: $0, isExpertReading: isExpertReading) } ?? preview,
            linking: linking,
            editing: editingContext,
            watch: watchContext,
            guidedFinish: guidedFinish,
            loadBreakdown: loadBreakdown,
            loadStrengthPrescription: loadStrengthPrescription,
            storedBreakdown: storedBreakdown,
            onDiscussWithCoach: onDiscuss
        )
        .task { await load() }
    }

    private var editingContext: SessionEditingContext? {
        guard let session, let editor else { return nil }
        return SessionEditingContext(
            session: session,
            editor: editor,
            onSaved: { self.session = $0 },
            onDeleted: { dismiss() }
        )
    }

    private var watchContext: SessionWatchContext? {
        guard let session, let tokenProvider, isGarminLinked,
              session.completed != true, WatchPushState.canSend(type: session.type) else { return nil }
        return SessionWatchContext(
            session: session,
            client: GarminWorkoutClient(),
            tokenProvider: tokenProvider,
            onSent: { Task { await reloadSession() } }
        )
    }

    private func load() async {
        guard let tokenProvider, preview.sessionId != nil else { return }
        let planned = PlannedSessionClient()
        editor = PlanEditor(
            mutator: planned,
            tokenProvider: tokenProvider,
            plan: PlanStore(client: planned, activityClient: ActivityClient(), tokenProvider: tokenProvider)
        )
        editor?.onChanged = { router.noteCalendarChanged() }
        await reloadSession()
        await loadGarminLink()
    }

    private func reloadSession() async {
        guard let tokenProvider, let id = preview.sessionId,
              let token = try? await tokenProvider(),
              let sessions = try? await PlannedSessionClient().plannedSessions(from: day, to: day, token: token),
              let fresh = sessions.first(where: { $0.id == id }) else { return }
        session = fresh
    }

    private func loadGarminLink() async {
        guard let tokenProvider, let token = try? await tokenProvider(),
              let status = try? await SharpitClient().syncStatus(token: token) else { return }
        isGarminLinked = status.providers.contains { $0.key == DisconnectableSource.garmin.statusKey }
    }
}

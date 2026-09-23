import SwiftUI

/// A prescription, as any screen can describe it.
///
/// Plan holds a `V1PlannedSessionItem`; Today holds a `SessionCardModel` projected for
/// display. Both open the same drawer, so both map into this rather than the drawer
/// growing a second initialiser — or, worse, Today growing a second drawer.
struct PlannedSessionPreview: Identifiable, Equatable {
    /// Addresses the prescription itself. Absent when the surface only knows a display
    /// line (a brick's group, say), which is why the coach button is conditional.
    let sessionId: String?
    let title: String
    let sport: String
    let symbolName: String
    let date: Date?
    let metrics: [PlannedSessionMetric]
    let notes: String?
    /// What to actually do. Empty when the surface has no structure to show.
    let steps: [V1PlannedSessionStep]
    /// True when the breakdown was inferred from duration and intensity rather than
    /// written — worth saying, because the athlete did not choose it.
    let stepsAreDerived: Bool
    let garminWorkoutId: String?
    let garminWorkoutScheduledDate: String?
    let garminWorkoutPushedAt: Date?

    var id: String { sessionId ?? title }

    init(
        sessionId: String?,
        title: String,
        sport: String,
        symbolName: String,
        date: Date?,
        metrics: [PlannedSessionMetric],
        notes: String?,
        steps: [V1PlannedSessionStep],
        stepsAreDerived: Bool,
        garminWorkoutId: String? = nil,
        garminWorkoutScheduledDate: String? = nil,
        garminWorkoutPushedAt: Date? = nil
    ) {
        self.sessionId = sessionId
        self.title = title
        self.sport = sport
        self.symbolName = symbolName
        self.date = date
        self.metrics = metrics
        self.notes = notes
        self.steps = steps
        self.stepsAreDerived = stepsAreDerived
        self.garminWorkoutId = garminWorkoutId
        self.garminWorkoutScheduledDate = garminWorkoutScheduledDate
        self.garminWorkoutPushedAt = garminWorkoutPushedAt
    }
}

/// What a screen hands the drawer so it can push its prescription to the watch.
struct SessionWatchPushContext: Sendable {
    let pusher: any PlannedSessionWatchPushing
    let tokenProvider: () async throws -> String
    let onPushed: @Sendable (PlannedSessionWatchPushResult) -> Void

    init(
        pusher: any PlannedSessionWatchPushing,
        tokenProvider: @escaping () async throws -> String,
        onPushed: @escaping @Sendable (PlannedSessionWatchPushResult) -> Void = { _ in }
    ) {
        self.pusher = pusher
        self.tokenProvider = tokenProvider
        self.onPushed = onPushed
    }
}

struct PlannedSessionMetric: Equatable {
    let label: String
    let value: String
}

extension PlannedSessionPreview {
    /// `isExpertReading` is passed rather than read from the environment: a preview is built
    /// outside any view, by the screen that owns the sheet.
    init(session: V1PlannedSessionItem, isExpertReading: Bool = false) {
        var metrics: [PlannedSessionMetric] = []
        if let durationMin = session.durationMin {
            metrics.append(PlannedSessionMetric(label: "Durée", value: "\(durationMin) min"))
        }
        if let intensity = session.intensity, !intensity.isEmpty {
            metrics.append(PlannedSessionMetric(label: "Intensité", value: intensity.capitalized))
        }
        // What the session is expected to cost. Shown in both readings, named for the one it
        // is read in (ADR 0006, reversing the omission this comment used to record).
        if let load = session.load, load > 0 {
            metrics.append(PlannedSessionMetric(
                label: isExpertReading ? "TSS" : "Charge",
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
            notes: session.notes,
            steps: session.breakdown?.steps ?? [],
            stepsAreDerived: session.breakdown?.derived ?? false,
            garminWorkoutId: session.garminWorkoutId,
            garminWorkoutScheduledDate: session.garminWorkoutScheduledDate,
            garminWorkoutPushedAt: session.garminWorkoutPushedAt
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

    init(card: SessionCardModel) {
        self.init(
            sessionId: card.plannedSessionId,
            title: card.title,
            sport: card.sport ?? "Séance",
            symbolName: SharpitSportTone.symbolName(for: card.sport ?? ""),
            date: nil,
            metrics: card.metrics.map {
                PlannedSessionMetric(
                    label: $0.label,
                    value: $0.unit.isEmpty ? $0.value : "\($0.value) \($0.unit)"
                )
            },
            notes: card.subtitle,
            // Today's payload carries the line, not the prescription behind it. The
            // breakdown arrives with the plan, so it is shown there.
            steps: [],
            stepsAreDerived: false
        )
    }
}

/// What a planned session holds, in a sheet.
///
/// A planned session has no detail screen to open — there is nothing recorded yet, only
/// an intention. A drawer says what is prescribed and offers the one action that makes
/// sense before it happens: asking the coach about it.
struct PlannedSessionDrawer: View {
    let preview: PlannedSessionPreview
    /// Nil where the screen cannot link, so the action is absent rather than dead.
    var linking: SessionLinkContext?
    /// Nil where the screen cannot push to watch.
    var watchPush: SessionWatchPushContext?
    /// Fetches the session's breakdown when the preview arrived without one — Today's
    /// payload carries the line, not the prescription behind it.
    var loadBreakdown: (() async -> V1PlannedSessionBreakdown?)?
    let onDiscussWithCoach: (CoachDiscussContext) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var showingLinkPicker = false
    @State private var showingReplaceConfirmation = false
    @State private var isPushingToWatch = false
    @State private var localWatchPush: PlannedSessionWatchPushResult?
    @State private var loadedBreakdown: V1PlannedSessionBreakdown?
    @State private var isLoadingBreakdown = false

    private var steps: [V1PlannedSessionStep] {
        preview.steps.isEmpty ? loadedBreakdown?.steps ?? [] : preview.steps
    }

    private var stepsAreDerived: Bool {
        preview.steps.isEmpty ? loadedBreakdown?.derived ?? false : preview.stepsAreDerived
    }

    private var currentWorkoutId: String? {
        localWatchPush?.workoutId ?? preview.garminWorkoutId
    }

    private var currentScheduledDate: String? {
        localWatchPush?.scheduledDate ?? preview.garminWorkoutScheduledDate
    }

    private var currentPushedAt: Date? {
        localWatchPush?.pushedAt ?? preview.garminWorkoutPushedAt
    }

    private var isAlreadyOnWatch: Bool {
        currentWorkoutId != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    header
                    // Without an id the coach cannot be told *which* session, and a tag
                    // naming the wrong one is worse than no tag.
                    if let sessionId = preview.sessionId {
                        CoachDiscussButton(title: "Discuter de cette séance") {
                            onDiscussWithCoach(
                                CoachDiscuss.describe(
                                    .plannedSession(sessionId: sessionId),
                                    name: preview.title
                                )
                            )
                            dismiss()
                        }
                    }
                    if !preview.metrics.isEmpty {
                        metricsRow
                    }
                    if !steps.isEmpty {
                        PlannedSessionBreakdownList(steps: steps, derived: stepsAreDerived)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if isLoadingBreakdown {
                        HStack(spacing: SharpitSpacing.xs) {
                            ProgressView()
                            Text("Chargement du déroulé…")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }
                    }
                    if let notes = preview.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                            SharpitEyebrow("Consigne")
                            Text(notes)
                                .font(SharpitTypography.body)
                                .foregroundStyle(SharpitColor.foreground)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(SharpitSpacing.cardPadding)
                        .sharpitSurface(.panel)
                    }
                    // Same reason as the coach button: linking needs to know *which* session.
                    if preview.sessionId != nil, linking != nil {
                        DrawerActionRow(
                            symbolName: "link",
                            title: "Lier à une séance réalisée",
                            subtitle: "Si elle n'a pas été rapprochée toute seule"
                        ) {
                            showingLinkPicker = true
                        }
                    }
                    if preview.sessionId != nil, let watchPush {
                        watchActionSection(context: watchPush)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.pageInset)
            }
            .background(SharpitCanvasBackground())
            .animation(SharpitMotion.reveal, value: steps.count)
            .task { await fetchBreakdownIfMissing() }
            .navigationTitle("Séance prévue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingLinkPicker) {
            if let sessionId = preview.sessionId, let linking {
                SessionLinkPicker(sessionId: sessionId, context: linking) {
                    showingLinkPicker = false
                    linking.onLinked()
                }
            }
        }
        .confirmationDialog(
            "Renvoyer cette séance à la montre ?",
            isPresented: $showingReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remplacer sur la montre", role: .destructive) {
                if let watchPush {
                    Task { await handleWatchPush(force: true, context: watchPush) }
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Cette séance est déjà présente sur votre montre Garmin. Renvoyer remplacera le workout existant.")
        }
    }

    @ViewBuilder
    private func watchActionSection(context: SessionWatchPushContext) -> some View {
        if isAlreadyOnWatch {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "applewatch.side.right")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
                    .frame(width: 28, height: 28)
                    .background(SharpitColor.chipSurface, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: SharpitSpacing.xs) {
                        Text("Sur la montre Garmin")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        Image(systemName: "checkmark.circle.fill")
                            .font(SharpitTypography.label)
                            .foregroundStyle(SharpitColor.primary)
                    }
                    if let currentScheduledDate {
                        Text("Prévue le \(currentScheduledDate)")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    showingReplaceConfirmation = true
                } label: {
                    HStack(spacing: 4) {
                        if isPushingToWatch {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(SharpitTypography.meta)
                        }
                        Text("Renvoyer")
                            .font(SharpitTypography.label)
                    }
                    .padding(.horizontal, SharpitSpacing.sm)
                    .padding(.vertical, SharpitSpacing.xs)
                    .background(SharpitColor.chipSurface, in: Capsule())
                    .foregroundStyle(SharpitColor.primary)
                }
                .buttonStyle(.plain)
                .disabled(isPushingToWatch)
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        } else {
            DrawerActionRow(
                symbolName: "applewatch.side.right",
                title: isPushingToWatch ? "Envoi vers la montre…" : "Envoyer à la montre",
                subtitle: isPushingToWatch ? "Transfert vers Garmin Connect en cours" : "Programme la séance dans Garmin Connect"
            ) {
                guard !isPushingToWatch else { return }
                Task { await handleWatchPush(force: false, context: context) }
            }
            .disabled(isPushingToWatch)
        }
    }

    private func handleWatchPush(force: Bool, context: SessionWatchPushContext) async {
        guard let sessionId = preview.sessionId else { return }
        isPushingToWatch = true
        SharpitHaptics.play(.soft)
        do {
            let token = try await context.tokenProvider()
            let result = try await context.pusher.pushToWatch(sessionId: sessionId, force: force, token: token)
            localWatchPush = result
            context.onPushed(result)
            SharpitHaptics.play(.success)
            toastCenter?.show(
                force ? "Workout renvoyé à la montre" : "Workout envoyé à la montre Garmin",
                symbol: "applewatch.side.right",
                tone: .success
            )
        } catch let error as PlannedSessionWatchPushError {
            switch error {
            case .alreadyPushed:
                showingReplaceConfirmation = true
            case .notConnected(let message):
                SharpitHaptics.play(.soft)
                toastCenter?.show(message, symbol: "exclamationmark.triangle", tone: .error)
            case .unsupported(let message), .failed(let message):
                SharpitHaptics.play(.soft)
                toastCenter?.show(message, symbol: "exclamationmark.triangle", tone: .error)
            }
        } catch {
            SharpitHaptics.play(.soft)
            toastCenter?.show(
                error.localizedDescription,
                symbol: "exclamationmark.triangle",
                tone: .error
            )
        }
        isPushingToWatch = false
    }

    private func fetchBreakdownIfMissing() async {
        guard preview.steps.isEmpty, loadedBreakdown == nil, let loadBreakdown else { return }
        isLoadingBreakdown = true
        loadedBreakdown = await loadBreakdown()
        isLoadingBreakdown = false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: preview.symbolName)
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitSportTone.label(for: preview.sport))
                Text(preview.sport)
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer(minLength: 0)
                if let date = preview.date {
                    Text(date.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            Text(preview.title)
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
        }
    }

    private var metricsRow: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.md) {
            ForEach(preview.metrics, id: \.label) { metric in
                VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
                    Text(metric.label)
                        .font(SharpitTypography.label)
                        .tracking(SharpitTypography.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Text(metric.value)
                        .font(SharpitTypography.data)
                        .tracking(SharpitTypography.dataTracking)
                        .foregroundStyle(SharpitColor.foreground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

/// A row that does one thing to the session in the drawer.
///
/// A row, not a filled block. The old coach button was a solid Forest slab with an arrow at
/// each end, which read as the loudest thing on a screen whose job is the session — and
/// the design law reserves filled surfaces for the verdict. This carries the same weight
/// as the panels around it: the panel surface, one leading mark.
struct DrawerActionRow: View {
    let symbolName: String
    let title: String
    var subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: symbolName)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
                    .frame(width: 28, height: 28)
                    .background(SharpitColor.chipSurface, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .accessibilityHidden(true)
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The way to hand a subject to the coach. A tinted pill near the top of the screen: it
/// is found because of where it sits and the one accent it carries, not because of its
/// size (ADR 0003).
struct CoachDiscussButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            SharpitHaptics.play(.soft)
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
        CoachDiscussButton(title: "Discuter de cette séance") {}
        CoachDiscussButton(title: "Discuter avec le coach") {}
    }
    .padding()
    .background(SharpitCanvasBackground())
}

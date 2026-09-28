import SwiftUI

/// A brick as any screen can describe it: its legs, in the order they are done.
///
/// Plan holds the legs whole; Résumé holds a line naming them, and the drawer reads their
/// steps from the plan when it opens — as the single session's drawer does.
struct PlannedBrickPreview: Identifiable, Equatable {
    let id: String
    let date: Date?
    var legs: [PlannedSessionPreview]

    /// « Vélo → Course »: the chain is what a brick trains.
    var chain: String { legs.map(\.sport).joined(separator: " → ") }

    var totalDurationMin: Int? {
        let durations = legs.compactMap(\.durationMin)
        return durations.isEmpty ? nil : durations.reduce(0, +)
    }
}

extension PlannedBrickPreview {
    init(brick: PlanBrick, isExpertReading: Bool = false) {
        self.init(
            id: brick.id,
            date: brick.date,
            legs: brick.legs.map { PlannedSessionPreview(session: $0, isExpertReading: isExpertReading) }
        )
    }

    /// Résumé's brick line: the legs it names, their steps still to be read.
    init?(card: SessionCardModel, date: Date?) {
        guard let legs = card.brickLegs, legs.count > 1 else { return nil }
        self.init(
            id: card.id,
            date: date,
            legs: legs.map { leg in
                PlannedSessionPreview(session: V1PlannedSessionItem(
                    id: leg.id,
                    date: date ?? .now,
                    title: leg.title,
                    type: leg.type,
                    durationMin: leg.durationMin
                ))
            }
        )
    }

    /// The legs as the plan holds them, in the brick's order — nil when the plan no longer
    /// has every one of them.
    func refreshed(from sessions: [V1PlannedSessionItem], isExpertReading: Bool = false) -> PlannedBrickPreview? {
        let byId = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let found = legs.compactMap { $0.sessionId.flatMap { byId[$0] } }
        guard found.count == legs.count else { return nil }
        var copy = self
        copy.legs = found.map { PlannedSessionPreview(session: $0, isExpertReading: isExpertReading) }
        return copy
    }
}

/// A brick, in a sheet: the legs one under the other, joined by the transition that makes
/// them a brick, each with its own steps.
///
/// Not the single session's drawer twice. What a brick trains is the change of sport without
/// a pause, so the chain leads — « Vélo → Course » — the total under it, and the transition sits
/// between the legs where it happens. A leg opens its own page, pushed here, for what belongs
/// to one session: the watch, a link to what was done.
struct BrickSessionDrawer: View {
    let brick: PlannedBrickPreview
    var linking: SessionLinkContext?
    var watchPush: SessionWatchPushContext?
    /// Reads the legs from the plan when the preview arrived without their steps.
    var loadLegs: (() async -> PlannedBrickPreview?)?
    let onDiscussWithCoach: (CoachDiscussContext) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loaded: PlannedBrickPreview?
    @State private var isLoading = false

    private var current: PlannedBrickPreview { loaded ?? brick }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    header
                    if let firstLeg = current.legs.first?.sessionId {
                        CoachDiscussButton(title: "Discuter de cet enchaînement") {
                            onDiscussWithCoach(
                                CoachDiscuss.describe(.plannedSession(sessionId: firstLeg), name: "Brick \(current.chain)")
                            )
                            dismiss()
                        }
                    }
                    legs
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.pageInset)
            }
            .background(SharpitCanvasBackground())
            .task { await loadIfNeeded() }
            .navigationTitle("Enchaînement")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PlannedSessionPreview.self) { leg in
                PlannedSessionDrawer(
                    preview: leg,
                    linking: linking,
                    watchPush: watchPush,
                    isEmbedded: true
                ) { context in
                    onDiscussWithCoach(context)
                    dismiss()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sharpitSheet()
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(spacing: SharpitSpacing.xs) {
                SharpitEyebrow("Brick · \(current.legs.count) étapes")
                Spacer(minLength: 0)
                if let date = current.date {
                    Text(date.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            BrickChainGlyphs(sports: current.legs.map(\.sport))
            Text(current.chain)
                .font(SharpitTypography.pageTitle)
                .tracking(SharpitTypography.pageTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
            if let total = current.totalDurationMin {
                Text("\(total) min enchaînées, sans pause entre les sports")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
    }

    private var legs: some View {
        VStack(spacing: 0) {
            ForEach(Array(current.legs.enumerated()), id: \.offset) { index, leg in
                if index > 0 {
                    BrickTransition(from: current.legs[index - 1].sport, to: leg.sport)
                }
                BrickLegPanel(index: index + 1, leg: leg, isLoading: isLoading && leg.steps.isEmpty)
            }
        }
    }

    private func loadIfNeeded() async {
        guard loaded == nil, let loadLegs, brick.legs.contains(where: \.steps.isEmpty) else { return }
        isLoading = true
        if let fresh = await loadLegs() {
            withAnimation(SharpitMotion.reveal) { loaded = fresh }
        }
        isLoading = false
    }
}

/// The sports of the chain, joined by arrows — the brick's mark where a session has one glyph.
private struct BrickChainGlyphs: View {
    let sports: [String]

    var body: some View {
        HStack(spacing: SharpitSpacing.xs) {
            ForEach(Array(sports.enumerated()), id: \.offset) { index, sport in
                if index > 0 {
                    Image(systemName: "arrow.right")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                SharpitSportBadge(type: V1ActivityType(sportLabel: sport))
            }
        }
        .accessibilityHidden(true)
    }
}

/// One leg: its place in the chain, its sport and length, its steps, and the way to it alone.
private struct BrickLegPanel: View {
    let index: Int
    let leg: PlannedSessionPreview
    let isLoading: Bool

    private var tone: Color { SharpitSportTone.label(for: leg.sport) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            NavigationLink(value: leg) {
                HStack(spacing: SharpitSpacing.sm) {
                    Text("\(index)")
                        .font(SharpitTypography.instrument)
                        .foregroundStyle(tone)
                        .frame(width: 30, height: 30)
                        .background(tone.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(leg.sport)
                            .font(SharpitTypography.label)
                            .tracking(SharpitTypography.labelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(tone)
                        Text(leg.title)
                            .font(SharpitTypography.cardTitle)
                            .tracking(SharpitTypography.cardTitleTracking)
                            .foregroundStyle(SharpitColor.foreground)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    if let duration = leg.durationMin {
                        Text("\(duration) min")
                            .font(SharpitTypography.instrument)
                            .foregroundStyle(SharpitColor.foreground)
                    }
                    Image(systemName: "chevron.right")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityLabel("Étape \(index), \(leg.sport), \(leg.title)")

            if !leg.steps.isEmpty {
                PlannedStepRail(steps: leg.steps)
                    .transition(.opacity)
            } else if isLoading {
                HStack(spacing: SharpitSpacing.xs) {
                    ProgressView()
                    Text("Chargement du déroulé…")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

/// Where one sport hands over to the next: what makes the legs a brick.
private struct BrickTransition: View {
    let from: String
    let to: String

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Rectangle()
                .fill(SharpitColor.primary.opacity(0.5))
                .frame(width: 2, height: 44)
                .padding(.leading, SharpitSpacing.cardPadding + 14)
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: "arrow.down")
                    .font(SharpitTypography.label)
                Text("Transition · enchaîne sans pause")
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
            }
            .foregroundStyle(SharpitColor.primary)
            .padding(.horizontal, SharpitSpacing.sm)
            .padding(.vertical, SharpitSpacing.xxs + 1)
            .background(SharpitColor.primary.opacity(0.10), in: Capsule())
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transition de \(from) à \(to), sans pause")
    }
}

#Preview {
    let date = Date.now
    BrickSessionDrawer(
        brick: PlannedBrickPreview(
            id: "brick",
            date: date,
            legs: [
                PlannedSessionPreview(session: V1PlannedSessionItem(
                    id: "bike", date: date, title: "Vélo tempo", type: "BIKE", durationMin: 60,
                    breakdown: V1PlannedSessionBreakdown(steps: [
                        V1PlannedSessionStep(key: "0-0", label: "Échauffement", detail: "15 min", group: "0"),
                        V1PlannedSessionStep(key: "1-0", label: "Bloc", detail: "8 min", target: "210–225 W", group: "1", repeatCount: 3),
                        V1PlannedSessionStep(key: "1-1", label: "Récup", detail: "3 min", group: "1", repeatCount: 3),
                    ])
                )),
                PlannedSessionPreview(session: V1PlannedSessionItem(
                    id: "run", date: date, title: "Course enchaînée", type: "RUN", durationMin: 20,
                    breakdown: V1PlannedSessionBreakdown(steps: [
                        V1PlannedSessionStep(key: "0-0", label: "Bloc", detail: "20 min", target: "4:30 – 4:45 /km", group: "0"),
                    ])
                )),
            ]
        )
    ) { _ in }
}

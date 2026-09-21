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

    var id: String { sessionId ?? title }
}

struct PlannedSessionMetric: Equatable {
    let label: String
    let value: String
}

extension PlannedSessionPreview {
    init(session: V1PlannedSessionItem) {
        // Charge/TSS is deliberately absent — a planning number, not something the athlete
        // acts on before a session.
        var metrics: [PlannedSessionMetric] = []
        if let durationMin = session.durationMin {
            metrics.append(PlannedSessionMetric(label: "Durée", value: "\(durationMin) min"))
        }
        if let intensity = session.intensity, !intensity.isEmpty {
            metrics.append(PlannedSessionMetric(label: "Intensité", value: intensity.capitalized))
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
            stepsAreDerived: session.breakdown?.derived ?? false
        )
    }

    /// Today's own line. Its metrics are already resolved for display, so they travel as
    /// they are rather than being recomputed from a shape Today does not have.
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
    let onDiscussWithCoach: (CoachDiscussContext) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingLinkPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                    header
                    if !preview.metrics.isEmpty {
                        metricsRow
                    }
                    if !preview.steps.isEmpty {
                        PlannedSessionBreakdownList(
                            steps: preview.steps,
                            derived: preview.stepsAreDerived
                        )
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
                    // Without an id the coach cannot be told *which* session, and a tag
                    // naming the wrong one is worse than no tag.
                    if let sessionId = preview.sessionId {
                        CoachDiscussButton(
                            title: "Discuter de cette séance",
                            subtitle: "Le coach verra la séance que tu regardes"
                        ) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SharpitSpacing.pageInset)
            }
            .background(SharpitCanvasBackground())
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
                    linking.onLinked()
                    dismiss()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: preview.symbolName)
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitSportTone.accent(for: preview.sport))
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

/// The button that hands a subject to the coach — the one call to action a screen carries,
/// so it takes the ink band and stands apart from the rows around it (ADR 0003).
struct CoachDiscussButton: View {
    let title: String
    var subtitle: String?
    let action: () -> Void

    var body: some View {
        Button {
            SharpitHaptics.play(.soft)
            action()
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(SharpitTypography.bodyEmphasis)
                    .frame(width: 40, height: 40)
                    .background(SharpitColor.inkSurfaceForeground.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SharpitTypography.bodyEmphasis)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(SharpitTypography.meta)
                            .opacity(0.78)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(SharpitTypography.bodyEmphasis)
                    .accessibilityHidden(true)
            }
            .padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.ink)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    VStack(spacing: SharpitSpacing.md) {
        CoachDiscussButton(
            title: "Discuter de cette séance",
            subtitle: "Le coach verra ce que tu regardes"
        ) {}
        CoachDiscussButton(title: "Discuter avec le coach") {}
    }
    .padding()
    .background(SharpitCanvasBackground())
}

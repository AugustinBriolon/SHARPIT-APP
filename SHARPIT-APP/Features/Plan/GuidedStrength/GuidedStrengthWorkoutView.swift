import AudioToolbox
import SwiftUI

/// Creates the logged STRENGTH activity and links it back to the planned session.
struct GuidedStrengthFinishContext {
    let client: any ActivityMutating
    let linker: any PlannedSessionLinking
    let tokenProvider: () async throws -> String
    /// Called once the activity exists (and the link was attempted).
    var onFinished: (String) -> Void = { _ in }
}

/// Full-screen phone follow — Strong's overview → sets card → rest ring, in Sharpit tokens.
struct GuidedStrengthWorkoutView: View {
    @State private var session: GuidedStrengthSession
    let finish: GuidedStrengthFinishContext

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .overview
    @State private var focusedExercise: String?
    @State private var restEndsAt: Date?
    @State private var restTotal = 0
    @State private var restPaused = false
    @State private var restPausedRemaining = 0
    @State private var restTask: Task<Void, Never>?
    @State private var rpe: Int?
    @State private var feeling: SessionFeeling?
    @State private var isSaving = false
    @State private var failure: String?
    @Environment(\.scenePhase) private var scenePhase
    /// Live text while a set field is focused — avoids reformatting mid-keystroke.
    @State private var repsDraft: [UUID: String] = [:]
    @State private var weightDraft: [UUID: String] = [:]
    @State private var durationDraft: [UUID: String] = [:]
    @FocusState private var focusedField: FieldFocus?
    /// Interactive-pop drag from the leading edge (exercise / rest → overview).
    @State private var edgeBackOffset: CGFloat = 0
    @StateObject private var heartRate = GuidedHeartRateMonitor()

    private enum FieldFocus: Hashable {
        case reps(UUID)
        case weight(UUID)
        case duration(UUID)
    }

    private enum Phase: Equatable {
        case overview
        case exercise
        case resting
        case summary
    }

    private var canEdgePopBack: Bool {
        phase == .exercise || phase == .resting
    }

    init(session: GuidedStrengthSession, finish: GuidedStrengthFinishContext) {
        _session = State(initialValue: session)
        self.finish = finish
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .overview:
                    overviewPage
                        .transition(Self.overviewTransition)
                case .exercise:
                    if let name = focusedExercise {
                        exercisePage(name: name)
                            .id(name)
                            .transition(Self.exerciseTransition)
                    } else {
                        overviewPage
                            .transition(Self.overviewTransition)
                    }
                case .resting:
                    restPage
                        .transition(Self.exerciseTransition)
                case .summary:
                    summaryPage
                        .transition(.opacity)
                }
            }
            .offset(x: canEdgePopBack ? edgeBackOffset : 0)
            .animation(SharpitMotion.reveal, value: phase)
            .animation(SharpitMotion.reveal, value: focusedExercise)
            .background(SharpitCanvasBackground())
            .navigationTitle(phase == .overview || phase == .summary ? session.title : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .overlay(alignment: .leading) {
                if canEdgePopBack {
                    edgeBackStrip
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .background(SharpitCanvasBackground())
        .sharpitRegularColumn()
        .onAppear {
            publishLiveActivityIfNeeded()
            heartRate.startIfEnabled()
        }
        .onDisappear {
            stopTimers()
            heartRate.stop()
        }
        .onChange(of: scenePhase) { _, scene in
            if scene == .background || scene == .inactive {
                // ActivityKit needs the request while we're still (barely) in session —
                // same pattern as the coach-reply Live Activity.
                publishLiveActivityIfNeeded()
            }
            if scene == .active {
                syncRestIfExpired()
            }
        }
        .onChange(of: phase) { _, _ in publishLiveActivityIfNeeded() }
        .onChange(of: focusedExercise) { _, _ in publishLiveActivityIfNeeded() }
    }

    /// Absolute rest end → displayed seconds (paused freezes the value).
    private var restRemaining: Int {
        if restPaused { return restPausedRemaining }
        guard let endsAt = restEndsAt else { return 0 }
        return max(0, Int(ceil(endsAt.timeIntervalSinceNow)))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if phase == .exercise || phase == .resting {
                Button {
                    goBackToOverview()
                } label: {
                    Label("Séance", systemImage: "chevron.backward")
                        .labelStyle(.titleAndIcon)
                }
            } else {
                // Menu (not confirmationDialog): opens from Quitter instead of page center.
                Menu {
                    Section("Les séries cochées ne seront pas enregistrées") {
                        Button("Quitter sans enregistrer", role: .destructive) {
                            stopTimers()
                            dismiss()
                        }
                    }
                } label: {
                    Text("Quitter")
                }
                .tint(SharpitColor.destructive)
                .disabled(isSaving)
            }
        }
        if phase == .overview || phase == .exercise || phase == .resting {
            ToolbarItem(placement: .principal) {
                HStack(spacing: SharpitSpacing.sm) {
                    sessionHeartRateChip
                    sessionElapsedClock
                }
            }
        }
        // Only on the session overview — never on a single exercise's sets.
        if phase == .overview {
            ToolbarItem(placement: .primaryAction) {
                Button("Terminer") {
                    stopTimers()
                    SharpitMotion.run { phase = .summary }
                }
                .disabled(session.completedCount == 0)
            }
        }
    }

    private var sessionElapsedClock: some View {
        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
            Text(PlannedSessionFormat.elapsedClock(Int(context.date.timeIntervalSince(session.startedAt))))
                .font(SharpitTypography.bodyEmphasis)
                .monospacedDigit()
                .foregroundStyle(SharpitColor.foreground)
                .contentTransition(.numericText())
                .accessibilityLabel("Durée de la séance")
        }
    }

    /// Tap to enable BLE HR and scan — no need to dig into Settings first.
    /// Toolbar `Label` drops its title; use Image + Text so the bpm stays visible.
    private var sessionHeartRateChip: some View {
        Button {
            if GuidedHeartRatePreference.isEnabled {
                GuidedHeartRatePreference.setEnabled(false)
                heartRate.stop()
            } else {
                GuidedHeartRatePreference.setEnabled(true)
                heartRate.startIfEnabled()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: heartRateChipSymbol)
                    .font(SharpitTypography.meta)
                if let bpm = heartRate.bpm, GuidedHeartRatePreference.isEnabled {
                    Text("\(bpm)")
                        .font(SharpitTypography.bodyEmphasis)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("bpm")
                        .font(SharpitTypography.meta)
                } else {
                    Text(heartRateChipTitle)
                        .font(SharpitTypography.meta)
                }
            }
            .foregroundStyle(heartRateChipColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Force the toolbar to refresh when bpm ticks (principal placement can stall).
        .id(heartRate.bpm ?? -1)
        .accessibilityLabel(heartRateAccessibilityLabel)
        .accessibilityHint("Active ou coupe le capteur cardiaque Bluetooth")
    }

    private var heartRateChipSymbol: String {
        guard GuidedHeartRatePreference.isEnabled else { return "heart" }
        switch heartRate.status {
        case .connected: return "heart.fill"
        case .unauthorized, .unavailable: return "heart.slash"
        default: return "heart"
        }
    }

    private var heartRateChipTitle: String {
        guard GuidedHeartRatePreference.isEnabled else { return "FC" }
        switch heartRate.status {
        case .scanning, .connecting: return "…"
        case .unauthorized, .unavailable: return "FC"
        case .connected where heartRate.bpm == nil: return "…"
        default: return "FC"
        }
    }

    private var heartRateChipColor: Color {
        if GuidedHeartRatePreference.isEnabled, heartRate.bpm != nil {
            return SharpitColor.destructive
        }
        if GuidedHeartRatePreference.isEnabled, heartRate.status == .connected {
            return SharpitColor.destructive
        }
        return SharpitColor.mutedForeground
    }

    private var heartRateAccessibilityLabel: String {
        if !GuidedHeartRatePreference.isEnabled {
            return "Connecter un capteur cardiaque"
        }
        if let bpm = heartRate.bpm {
            return "Fréquence cardiaque \(bpm) battements par minute"
        }
        switch heartRate.status {
        case .scanning, .connecting: return "Recherche du capteur cardiaque"
        case .unauthorized, .unavailable: return "Capteur cardiaque indisponible"
        default: return "Capteur cardiaque"
        }
    }

    // MARK: - Overview (image 3)

    private var overviewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    Text(session.title)
                        .font(SharpitTypography.pageTitle)
                        .tracking(SharpitTypography.pageTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(overviewSubtitle)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    SharpitEyebrow("Exercices")
                    VStack(spacing: SharpitSpacing.sm) {
                        ForEach(Array(session.exerciseGroups.enumerated()), id: \.element.id) { offset, group in
                            overviewExerciseRow(group: group, order: offset + 1)
                        }
                    }
                    .padding(SharpitSpacing.sm)
                    .sharpitSurface(.panelAlt)
                }

                Button {
                    stopTimers()
                    SharpitMotion.run { phase = .summary }
                } label: {
                    Text(session.completedCount == 0 ? "Aucune série encore" : "Terminer la séance")
                        .font(SharpitTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SharpitSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(SharpitColor.inkSurface)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
                .disabled(session.completedCount == 0)
            }
            .padding(SharpitSpacing.pageInset)
        }
    }

    private var overviewSubtitle: String {
        let names = session.exerciseGroups.map(\.name)
        if names.count <= 3 { return names.joined(separator: " · ") }
        return "\(names.prefix(3).joined(separator: " · ")) · +\(names.count - 3)"
    }

    private func overviewExerciseRow(group: GuidedStrengthExerciseGroup, order: Int) -> some View {
        let done = group.doneCount(in: session.targets)
        let total = group.indices.count
        let volume = group.volumeKg(in: session.targets)
        return Button {
            SharpitMotion.run {
                focusedExercise = group.name
                phase = .exercise
            }
        } label: {
            HStack(spacing: SharpitSpacing.sm) {
                if let thumb = ExerciseMediaCatalog.thumbURL(
                    catalogId: group.exerciseCatalogId,
                    name: group.name
                ) {
                    GuidedExerciseThumbView(url: thumb, size: 44)
                } else {
                    Text("\(order)")
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.inkSurfaceForeground)
                        .frame(width: 44, height: 44)
                        .background(SharpitColor.inkSurface, in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(SharpitTypography.cardTitle)
                        .tracking(SharpitTypography.cardTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                    Text(done == total && total > 0 ? "Terminé" : "\(done)/\(total) séries")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(total) série\(total == 1 ? "" : "s")")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    if volume > 0 {
                        Text("\(GuidedStrengthSetTarget.volumeFigure(volume)) kg")
                            .font(SharpitTypography.bodyEmphasis)
                            .monospacedDigit()
                            .foregroundStyle(SharpitColor.foreground)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
    }

    // MARK: - Exercise card (image 1)

    private static let overviewTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )
    private static let exerciseTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
    )

    private func exercisePage(name: String) -> some View {
        let group = session.exerciseGroups.first { $0.name == name }
        let volume = group?.volumeKg(in: session.targets) ?? 0
        let sets = group?.indices.map { session.targets[$0] } ?? []
        let gifURL = ExerciseMediaCatalog.gifURL(
            catalogId: group?.exerciseCatalogId,
            name: name
        )
        // List (not ScrollView) so trailing swipeActions can reveal trash.
        return List {
            Section {
                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    if let gifURL {
                        GuidedExerciseMediaView(url: gifURL, height: 188)
                        Text(ExerciseMediaCatalog.attribution)
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }

                    HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                        if gifURL == nil {
                            Image(systemName: "dumbbell.fill")
                                .font(SharpitTypography.bodyEmphasis)
                                .foregroundStyle(SharpitColor.primary)
                                .frame(width: 40, height: 40)
                                .background(SharpitColor.chipSurface, in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(SharpitTypography.sectionTitle)
                                .tracking(SharpitTypography.sectionTitleTracking)
                                .foregroundStyle(SharpitColor.foreground)
                            if let notes = group?.notes, !notes.isEmpty {
                                Text(notes)
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                            } else {
                                Text("Séries prescrites")
                                    .font(SharpitTypography.meta)
                                    .foregroundStyle(SharpitColor.mutedForeground)
                            }
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Volume")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                            Text(volume > 0 ? "\(GuidedStrengthSetTarget.volumeFigure(volume)) kg" : "—")
                                .font(SharpitTypography.bodyEmphasis)
                                .monospacedDigit()
                                .foregroundStyle(SharpitColor.foreground)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(
                    top: SharpitSpacing.pageInset,
                    leading: SharpitSpacing.pageInset,
                    bottom: SharpitSpacing.sm,
                    trailing: SharpitSpacing.pageInset
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(sets) { set in
                    setRow(id: set.id)
                        .listRowInsets(EdgeInsets(
                            top: SharpitSpacing.xs,
                            leading: SharpitSpacing.pageInset,
                            bottom: SharpitSpacing.xs,
                            trailing: SharpitSpacing.pageInset
                        ))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if session.canRemoveSet(id: set.id) {
                                    SharpitSwipeDeleteButton {
                                        session.removeSet(id: set.id)
                                    }
                                }
                            }
                }

                Button {
                    session.addSet(toExercise: name)
                } label: {
                    Text("+ Ajouter une série")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SharpitSpacing.sm)
                        .overlay(
                            RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                .foregroundStyle(SharpitColor.analysisGrid)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(
                    top: SharpitSpacing.xs,
                    leading: SharpitSpacing.pageInset,
                    bottom: SharpitSpacing.pageInset,
                    trailing: SharpitSpacing.pageInset
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focusedField = nil }
            }
        }
    }

    @ViewBuilder
    private func setRow(id: UUID) -> some View {
        if let set = session.targets.first(where: { $0.id == id }) {
            HStack(spacing: SharpitSpacing.sm) {
                Text("\(set.setNumber)")
                    .font(SharpitTypography.label)
                    .foregroundStyle(SharpitColor.inkSurfaceForeground)
                    .frame(width: 28, height: 28)
                    .background(SharpitColor.inkSurface, in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))

                if set.isHold {
                    TextField("0", text: durationText(for: set.id))
                        .keyboardType(.numberPad)
                        .font(SharpitTypography.instrument)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                        .focused($focusedField, equals: .duration(set.id))
                        .frame(minWidth: 44, maxWidth: 72, alignment: .leading)
                        .accessibilityLabel("Durée en secondes")
                    Text("s")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Spacer(minLength: 0)
                } else {
                    TextField("0", text: repsText(for: set.id))
                        .keyboardType(.numberPad)
                        .font(SharpitTypography.instrument)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                        .focused($focusedField, equals: .reps(set.id))
                        .frame(minWidth: 36, maxWidth: 56, alignment: .leading)
                        .accessibilityLabel("Répétitions")

                    Text("×")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)

                    TextField("0", text: weightText(for: set.id))
                        .keyboardType(.decimalPad)
                        .font(SharpitTypography.instrument)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                        .focused($focusedField, equals: .weight(set.id))
                        .frame(minWidth: 52, maxWidth: 80, alignment: .leading)
                        .accessibilityLabel("Charge en kilogrammes")

                    Text("kg")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)

                    Spacer(minLength: 0)
                }

                Button {
                    if set.isDone {
                        session.uncompleteSet(id: set.id)
                    } else {
                        completeSet(id: set.id)
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(SharpitTypography.label)
                        .foregroundStyle(set.isDone ? SharpitColor.inkSurfaceForeground : SharpitColor.mutedForeground)
                        .frame(width: 32, height: 32)
                        .background(
                            set.isDone ? SharpitColor.primary : SharpitColor.chipSurface,
                            in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set.isDone ? "Série faite" : "Marquer la série")
            }
            .padding(.horizontal, SharpitSpacing.sm)
            .padding(.vertical, SharpitSpacing.sm)
            .background(SharpitColor.analysisSurface, in: RoundedRectangle(cornerRadius: SharpitRadius.panel, style: .continuous))
        }
    }

    // MARK: - Rest (image 2)

    private var restPage: some View {
        let last = lastCompletedSet
        let next = session.current
        return VStack(spacing: SharpitSpacing.lg) {
            VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                Text("Repos")
                    .font(SharpitTypography.pageTitle)
                    .tracking(SharpitTypography.pageTitleTracking)
                    .foregroundStyle(SharpitColor.foreground)
                Text(restSubtitle(next: next))
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let remaining = restRemaining
                let progress = restTotal > 0 ? Double(restTotal - remaining) / Double(restTotal) : 1
                ZStack {
                    Circle()
                        .stroke(SharpitColor.analysisGrid, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: min(max(progress, 0), 1))
                        .stroke(SharpitColor.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: SharpitSpacing.xs) {
                        Text(PlannedSessionFormat.restClock(remaining))
                            .font(SharpitTypography.heroScore)
                            .tracking(SharpitTypography.heroScoreTracking)
                            .monospacedDigit()
                            .foregroundStyle(SharpitColor.foreground)
                            .contentTransition(.numericText())
                        Text("jusqu’à la prochaine série")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                    }
                }
                .frame(width: 220, height: 220)
                .frame(maxWidth: .infinity)
                .onChange(of: remaining) { _, value in
                    if value <= 0 { syncRestIfExpired() }
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dernière")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Text(last?.readoutLine ?? "—")
                        .font(SharpitTypography.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Prochaine")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                    Text(next?.readoutLine ?? "—")
                        .font(SharpitTypography.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(SharpitColor.foreground)
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)

            Spacer(minLength: 0)

            HStack(spacing: SharpitSpacing.sm) {
                Button {
                    extendRest(by: 15)
                } label: {
                    Text("+15 s")
                        .font(SharpitTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SharpitSpacing.sm)
                }
                .buttonStyle(.bordered)

                Button {
                    toggleRestPause()
                } label: {
                    Label(restPaused ? "Reprendre" : "Pause", systemImage: restPaused ? "play.fill" : "pause.fill")
                        .font(SharpitTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SharpitSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(SharpitColor.primary)

                Button {
                    endRest()
                } label: {
                    Label("Passer", systemImage: "forward.end.fill")
                        .font(SharpitTypography.bodyEmphasis)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SharpitSpacing.sm)
                }
                .buttonStyle(.borderedProminent)
                .tint(SharpitColor.inkSurface)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
            }
        }
        .padding(SharpitSpacing.pageInset)
    }

    private func restSubtitle(next: GuidedStrengthSetTarget?) -> String {
        guard let next else { return "Dernière série terminée" }
        return "\(next.exerciseName) · série \(next.setNumber) sur \(next.setCount)"
    }

    private var lastCompletedSet: GuidedStrengthSetTarget? {
        session.targets.last(where: \.isDone)
    }

    // MARK: - Summary

    private var summaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
                    Text(session.title)
                        .font(SharpitTypography.pageTitle)
                        .tracking(SharpitTypography.pageTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("\(session.completedCount) série\(session.completedCount == 1 ? "" : "s") cochée\(session.completedCount == 1 ? "" : "s")")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                // Feedback first — the job of this screen — then the set list as context.
                feedbackPanel

                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    SharpitEyebrow("Exercices")
                    ForEach(Array(session.exerciseGroups.enumerated()), id: \.element.id) { offset, group in
                        let volume = group.volumeKg(in: session.targets)
                        let done = group.doneCount(in: session.targets)
                        HStack {
                            Text("\(offset + 1)")
                                .font(SharpitTypography.label)
                                .foregroundStyle(SharpitColor.inkSurfaceForeground)
                                .frame(width: 24, height: 24)
                                .background(SharpitColor.inkSurface, in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous))
                            Text(group.name)
                                .font(SharpitTypography.cardTitle)
                            Spacer()
                            Text("\(done) série\(done == 1 ? "" : "s")")
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.mutedForeground)
                            if volume > 0 {
                                Text("\(GuidedStrengthSetTarget.volumeFigure(volume)) kg")
                                    .font(SharpitTypography.bodyEmphasis)
                                    .monospacedDigit()
                            }
                        }
                        .padding(SharpitSpacing.sm)
                        .sharpitSurface(.panel)
                    }
                }

                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SharpitSpacing.sm)
                    } else {
                        Text(session.completedCount == 0 ? "Fermer" : "Enregistrer la séance")
                            .font(SharpitTypography.bodyEmphasis)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, SharpitSpacing.sm)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(SharpitColor.inkSurface)
                .foregroundStyle(SharpitColor.inkSurfaceForeground)
                .disabled(isSaving)
            }
            .padding(SharpitSpacing.pageInset)
        }
    }

    private var feedbackPanel: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitEyebrow("Comment c’était ?")
            rpePicker
            feelingPicker
        }
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }

    private var rpePicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                SharpitFieldLabel("Effort perçu")
                Spacer()
                Text(rpe.map(String.init) ?? "—")
                    .font(SharpitTypography.instrument)
                    .monospacedDigit()
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.numericText())
                Text("RPE")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            // Full-width ticks — finger tracks 1:1 across the scale (Apple direct manipulation).
            GuidedRPEScale(value: $rpe)
        }
    }

    /// Leading-edge strip — same idea as iOS interactive pop, without fighting the set List.
    private var edgeBackStrip: some View {
        Color.clear
            .frame(width: 22)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { value in
                        let dx = max(0, value.translation.width)
                        // Soft rubber past ~120pt so the page resists instead of flying off.
                        edgeBackOffset = dx < 120 ? dx : 120 + (dx - 120) * 0.25
                    }
                    .onEnded { value in
                        let projected = value.translation.width + value.predictedEndTranslation.width * 0.35
                        let shouldPop = value.translation.width > 72 || projected > 140
                        if shouldPop {
                            edgeBackOffset = 0
                            goBackToOverview()
                        } else {
                            withAnimation(SharpitMotion.selection) { edgeBackOffset = 0 }
                        }
                    }
            )
            .accessibilityHidden(true)
    }

    private func goBackToOverview() {
        SharpitMotion.run {
            focusedExercise = nil
            stopRest()
            phase = .overview
            edgeBackOffset = 0
        }
    }

    private var feelingPicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitFieldLabel("Ressenti")
            HStack(spacing: SharpitSpacing.xs) {
                ForEach(SessionFeeling.allCases) { option in
                    let selected = feeling == option
                    Button {
                        SharpitHaptics.play(.notch(major: false))
                        SharpitMotion.run(SharpitMotion.selection) {
                            feeling = option
                        }
                    } label: {
                        Text(option.emoji)
                            .font(.system(size: 32))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .padding(.vertical, SharpitSpacing.xs)
                            .background(
                                selected ? SharpitColor.chipSurface : Color.clear,
                                in: RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                            )
                            .opacity(feeling == nil || selected ? 1 : 0.38)
                            .scaleEffect(selected ? 1.06 : 1)
                            .animation(SharpitMotion.selection, value: feeling)
                    }
                    .buttonStyle(.sharpitPressable)
                    .accessibilityLabel(option.storedValue)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            // Reserve height so selecting doesn't jump the layout (CLS).
            Text(feeling?.hint ?? " ")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(feeling == nil)
        }
    }

    // MARK: - Actions

    private func completeSet(id: UUID) {
        guard let index = session.targets.firstIndex(where: { $0.id == id }) else { return }
        let completed = session.targets[index]
        session.completeSet(id: id)
        SharpitHaptics.play(.notch(major: true))
        AudioServicesPlaySystemSound(1057)

        let nextSame = session.targets.first {
            $0.exerciseName == completed.exerciseName && !$0.isDone && !$0.isSkipped
        }
        if let rest = completed.restSec, completed.restIsTimed, rest > 0, nextSame != nil {
            SharpitMotion.run {
                startRest(seconds: rest, next: nextSame)
                phase = .resting
            }
        }
    }

    private func startRest(seconds: Int, next: GuidedStrengthSetTarget? = nil) {
        let nextSet = next ?? session.current
        let resuming = restPaused
        let endsAt = Date().addingTimeInterval(TimeInterval(max(seconds, 0)))
        restTask?.cancel()
        restEndsAt = endsAt
        if !resuming { restTotal = seconds }
        restPaused = false
        restPausedRemaining = 0
        GuidedStrengthRestLiveActivityController.shared.startRest(
            sessionTitle: session.title,
            startedAt: session.startedAt,
            endsAt: endsAt,
            nextExercise: nextSet?.exerciseName ?? "",
            nextSetLine: nextSet.map { "série \($0.setNumber) · \($0.readoutLine)" } ?? ""
        )
        scheduleRestWake(at: endsAt)
    }

    private func extendRest(by seconds: Int) {
        if restPaused {
            restPausedRemaining += seconds
            restTotal += seconds
            GuidedStrengthRestLiveActivityController.shared.setPaused(remaining: restPausedRemaining)
            return
        }
        guard let endsAt = restEndsAt else { return }
        let nextEnds = endsAt.addingTimeInterval(TimeInterval(seconds))
        restEndsAt = nextEnds
        restTotal += seconds
        GuidedStrengthRestLiveActivityController.shared.updateEndsAt(nextEnds)
        scheduleRestWake(at: nextEnds)
    }

    private func toggleRestPause() {
        if restPaused {
            startRest(seconds: max(restPausedRemaining, 1))
            return
        }
        let remaining = restRemaining
        restTask?.cancel()
        restTask = nil
        restEndsAt = nil
        restPaused = true
        restPausedRemaining = remaining
        GuidedStrengthRestLiveActivityController.shared.setPaused(remaining: remaining)
    }

    private func scheduleRestWake(at endsAt: Date) {
        restTask?.cancel()
        restTask = Task { @MainActor in
            let delay = endsAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            finishRestCountdown()
        }
    }

    private func syncRestIfExpired() {
        guard phase == .resting, !restPaused else { return }
        guard let endsAt = restEndsAt, endsAt.timeIntervalSinceNow <= 0 else { return }
        finishRestCountdown()
    }

    private func finishRestCountdown() {
        guard phase == .resting else { return }
        AudioServicesPlaySystemSound(1005)
        SharpitHaptics.play(.notch(major: true))
        endRest()
    }

    private func endRest() {
        stopRest()
        SharpitMotion.run {
            if let current = session.current {
                focusedExercise = current.exerciseName
                phase = .exercise
            } else {
                phase = .overview
            }
        }
    }

    private func stopRest(keepingLiveActivity: Bool = true) {
        restTask?.cancel()
        restTask = nil
        restEndsAt = nil
        restTotal = 0
        restPaused = false
        restPausedRemaining = 0
        if keepingLiveActivity {
            publishLiveActivityIfNeeded(forceActive: true)
        }
    }

    private func stopTimers() {
        stopRest(keepingLiveActivity: false)
        GuidedStrengthRestLiveActivityController.shared.end()
    }

    private func publishLiveActivityIfNeeded(forceActive: Bool = false) {
        guard phase == .overview || phase == .exercise || phase == .resting else { return }
        if phase == .resting, !forceActive, restEndsAt != nil || restPaused { return }

        let focus = focusedExercise
        let current = session.current
        let exercise = focus ?? current?.exerciseName ?? ""
        let detail: String = {
            if let current, current.exerciseName == exercise {
                return "série \(current.setNumber) · \(current.readoutLine)"
            }
            if let focus,
               let group = session.exerciseGroups.first(where: { $0.name == focus }) {
                let done = group.doneCount(in: session.targets)
                return "\(done)/\(group.indices.count) séries"
            }
            return "\(session.completedCount) série\(session.completedCount == 1 ? "" : "s")"
        }()

        if forceActive {
            GuidedStrengthRestLiveActivityController.shared.resumeActive(
                nextExercise: exercise,
                nextSetLine: detail
            )
        }
        GuidedStrengthRestLiveActivityController.shared.ensureActive(
            sessionTitle: session.title,
            startedAt: session.startedAt,
            nextExercise: exercise,
            nextSetLine: detail
        )
    }

    private func save() async {
        if session.completedCount == 0 {
            dismiss()
            return
        }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        let draft = session.activityDraft(rpe: rpe, feeling: feeling)
        guard draft.missingRequirement == nil else {
            failure = draft.missingRequirement
            return
        }
        do {
            let token = try await finish.tokenProvider()
            let activityId = try await SharpitRetry.run {
                try await finish.client.createActivity(draft.creation(), token: token)
            }
            if let plannedId = session.plannedSessionId {
                try? await finish.linker.link(sessionId: plannedId, activityId: activityId, token: token)
            }
            finish.onFinished(activityId)
            dismiss()
        } catch let SharpitAPIError.message(reason) {
            failure = reason
        } catch {
            failure = SharpitErrorGuidance.message(for: error, subject: "La séance")
        }
    }

    private func repsText(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                if focusedField == .reps(id), let draft = repsDraft[id] { return draft }
                guard let reps = session.targets.first(where: { $0.id == id })?.loggedReps else { return "" }
                return "\(reps)"
            },
            set: { text in
                repsDraft[id] = text
                guard let index = session.targets.firstIndex(where: { $0.id == id }) else { return }
                let digits = text.filter(\.isNumber)
                if let value = Int(digits) {
                    session.targets[index].loggedReps = min(max(value, 0), 500)
                } else if digits.isEmpty {
                    session.targets[index].loggedReps = 0
                }
            }
        )
    }

    private func weightText(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                if focusedField == .weight(id), let draft = weightDraft[id] { return draft }
                guard let kg = session.targets.first(where: { $0.id == id })?.loggedWeightKg else { return "" }
                return ActivityDraft.number(kg, digits: 1)
            },
            set: { text in
                weightDraft[id] = text
                guard let index = session.targets.firstIndex(where: { $0.id == id }) else { return }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    session.targets[index].loggedWeightKg = nil
                } else if let value = ActivityDraft.parse(trimmed) {
                    session.targets[index].loggedWeightKg = value
                }
            }
        )
    }

    private func durationText(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                if focusedField == .duration(id), let draft = durationDraft[id] { return draft }
                guard let sec = session.targets.first(where: { $0.id == id })?.loggedDurationSec else { return "" }
                return "\(sec)"
            },
            set: { text in
                durationDraft[id] = text
                guard let index = session.targets.firstIndex(where: { $0.id == id }) else { return }
                let digits = text.filter(\.isNumber)
                if let value = Int(digits) {
                    session.targets[index].loggedDurationSec = min(max(value, 0), 3600)
                } else if digits.isEmpty {
                    session.targets[index].loggedDurationSec = 0
                }
            }
        )
    }
}

/// Full-width RPE tick scale — finger tracks 1:1; every unit spans the panel.
private struct GuidedRPEScale: View {
    @Binding var value: Int?
    private let range = 1...10

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(range), id: \.self) { mark in
                        let selected = value == mark
                        let major = mark == 1 || mark == 5 || mark == 10
                        Capsule()
                            .fill(
                                selected
                                    ? SharpitColor.primary
                                    : SharpitColor.foreground.opacity(major ? 0.45 : 0.22)
                            )
                            .frame(width: selected ? 3 : (major ? 2 : 1.5), height: selected ? 36 : (major ? 28 : 18))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            SharpitHaptics.prepare()
                            let t = min(max(gesture.location.x / width, 0), 1)
                            let next = range.lowerBound + Int((t * CGFloat(range.count - 1)).rounded())
                            guard next != value else { return }
                            value = next
                            SharpitHaptics.play(.notch(major: next == 1 || next == 5 || next == 10))
                        }
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Effort perçu")
                .accessibilityValue(value.map { "\($0) RPE" } ?? "Non renseigné")
                .accessibilityAdjustableAction { direction in
                    let current = value ?? 5
                    let next = direction == .increment ? current + 1 : current - 1
                    guard range.contains(next) else { return }
                    value = next
                    SharpitHaptics.play(.notch(major: next == 5 || next == 10))
                }
            }
            .frame(height: 44)

            HStack {
                Text("1")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer()
                Text("10")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
        }
        .onAppear {
            if value == nil { value = 5 }
        }
    }
}

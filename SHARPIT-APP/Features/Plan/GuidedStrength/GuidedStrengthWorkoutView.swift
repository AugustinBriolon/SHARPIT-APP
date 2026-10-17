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
    /// Pushed pages over the overview — the system push/pop and its edge swipe.
    @State private var path: [Route] = []
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
    @StateObject private var heartRate = GuidedHeartRateMonitor()
    @State private var showingHeartRatePicker = false

    private enum FieldFocus: Hashable {
        case reps(UUID)
        case weight(UUID)
        case duration(UUID)
    }

    private enum Phase: Equatable {
        case overview
        case summary
    }

    private enum Route: Hashable {
        case exercise(String)
        case rest
    }

    private var focusedExercise: String? {
        guard case let .exercise(name) = path.last else { return nil }
        return name
    }

    private var isResting: Bool { path.last == .rest }

    init(session: GuidedStrengthSession, finish: GuidedStrengthFinishContext) {
        _session = State(initialValue: session)
        self.finish = finish
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch phase {
                case .overview:
                    overviewPage
                        .transition(.move(edge: .leading).combined(with: .opacity))
                case .summary:
                    summaryPage
                        .transition(.opacity)
                }
            }
            .animation(SharpitMotion.reveal, value: phase)
            .background(SharpitCanvasBackground())
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(for: Route.self) { route in
                Group {
                    switch route {
                    case let .exercise(name): exercisePage(name: name)
                    case .rest: restPage
                    }
                }
                .background(SharpitCanvasBackground())
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { sessionStatus }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .background(SharpitCanvasBackground())
        .sharpitRegularColumn()
        .sheet(isPresented: $showingHeartRatePicker) {
            GuidedHeartRatePickerSheet(monitor: heartRate)
        }
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
        .onChange(of: path) { old, new in
            // Back from the rest page (button or edge swipe) ends the rest, as before.
            if old.last == .rest, new.last != .rest, restEndsAt != nil || restPaused {
                stopRest()
            }
            publishLiveActivityIfNeeded()
        }
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
        if phase == .overview {
            ToolbarItem(placement: .principal) { sessionStatus }
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

    private var sessionStatus: some View {
        HStack(spacing: SharpitSpacing.sm) {
            sessionHeartRateChip
            sessionElapsedClock
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

    /// Tap opens the BLE device picker. BPM only after a real connection.
    /// Toolbar `Label` drops its title; use Image + Text so the bpm stays visible.
    private var sessionHeartRateChip: some View {
        Button {
            showingHeartRatePicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: heartRateChipSymbol)
                    .font(SharpitTypography.meta)
                if let bpm = heartRate.bpm, heartRate.status == .connected {
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
            .fixedSize(horizontal: true, vertical: false)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Force the toolbar to refresh when bpm ticks (principal placement can stall).
        .id("\(heartRate.status)-\(heartRate.bpm ?? -1)")
        .accessibilityLabel(heartRateAccessibilityLabel)
        .accessibilityHint("Choisir un capteur cardiaque Bluetooth")
    }

    private var heartRateChipSymbol: String {
        switch heartRate.status {
        case .connected: return "heart.fill"
        case .unauthorized, .unavailable: return "heart.slash"
        default: return "heart"
        }
    }

    private var heartRateChipTitle: String {
        switch heartRate.status {
        case .scanning, .connecting: return "…"
        case .connected where heartRate.bpm == nil: return "…"
        case .connected: return "FC"
        default: return "FC"
        }
    }

    private var heartRateChipColor: Color {
        if heartRate.status == .connected {
            return SharpitColor.destructive
        }
        return SharpitColor.mutedForeground
    }

    private var heartRateAccessibilityLabel: String {
        if let bpm = heartRate.bpm, heartRate.status == .connected {
            return "Fréquence cardiaque \(bpm) battements par minute"
        }
        switch heartRate.status {
        case .scanning, .connecting: return "Recherche du capteur cardiaque"
        case .unauthorized, .unavailable: return "Capteur cardiaque indisponible"
        case .connected: return "Capteur cardiaque connecté"
        default: return "Connecter un capteur cardiaque"
        }
    }

    // MARK: - Overview (image 3)

    private var overviewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(SharpitTypography.cardTitle)
                        .tracking(SharpitTypography.cardTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(overviewSubtitle)
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    Text("Exercices")
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body))
                        .foregroundStyle(SharpitColor.mutedForeground)
                    SharpitInsetGroup {
                        ForEach(Array(session.exerciseGroups.enumerated()), id: \.element.id) { offset, group in
                            overviewExerciseRow(group: group, order: offset + 1)
                        }
                    }
                }

                SharpitProgressBar(
                    label: "Séries faites",
                    value: "\(session.completedCount) / \(session.targets.count)",
                    fraction: session.targets.isEmpty ? 0 : Double(session.completedCount) / Double(session.targets.count)
                )

                SharpitPrimaryButton(title: session.completedCount == 0 ? "Aucune série encore" : "Terminer la séance") {
                    stopTimers()
                    SharpitMotion.run { phase = .summary }
                }
                .disabled(session.completedCount == 0)
                .opacity(session.completedCount == 0 ? 0.5 : 1)
            }
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
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
        return NavigationLink(value: Route.exercise(group.name)) {
            HStack(spacing: SharpitSpacing.sm) {
                if let thumb = ExerciseMediaCatalog.thumbURL(
                    catalogId: group.exerciseCatalogId,
                    name: group.name
                ) {
                    GuidedExerciseThumbView(url: thumb, size: SharpitTokens.chipSize)
                } else {
                    SharpitNumberChip(number: order)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.leading)
                    if done == total, total > 0 {
                        SharpitPill("Terminé", style: .lime)
                    }
                }

                Spacer(minLength: SharpitSpacing.xs)

                Text("\(done)/\(total) séries")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline, digits: true))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize()
                if volume > 0 {
                    volumeFigure(volume)
                }
            }
            .padding(.horizontal, SharpitSpacing.rowPaddingX)
            .padding(.vertical, SharpitSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: SharpitSpacing.rowHeight, alignment: .leading)
            .sharpitSurface(.row)
        }
        .buttonStyle(.sharpitPressable)
    }

    /// Trailing volume, width reserved for the widest figure so 3–5 digits never move the row.
    private func volumeFigure(_ volume: Double) -> some View {
        ZStack(alignment: .trailing) {
            SharpitRowFigure(value: GuidedStrengthSetTarget.volumeFigureTemplate, unit: "kg")
                .hidden()
            SharpitRowFigure(
                value: volume > 0 ? GuidedStrengthSetTarget.volumeFigure(volume) : "—",
                unit: volume > 0 ? "kg" : nil
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(volume > 0 ? "\(GuidedStrengthSetTarget.volumeFigure(volume)) kilogrammes" : "Aucun volume")
    }

    // MARK: - Exercise card (image 1)

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
                            SharpitIconTile(symbol: "dumbbell.fill")
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(SharpitTypography.cardTitle)
                                .tracking(SharpitTypography.cardTitleTracking)
                                .foregroundStyle(SharpitColor.foreground)
                            Text(group?.notes.flatMap { $0.isEmpty ? nil : $0 } ?? "Séries prescrites")
                                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                                .foregroundStyle(SharpitColor.mutedForeground)
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Volume")
                                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                                .foregroundStyle(SharpitColor.mutedForeground)
                            volumeFigure(volume)
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

                SharpitDashedAddButton(title: "Ajouter une série") {
                    session.addSet(toExercise: name)
                }
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
                SharpitNumberChip(number: set.setNumber)

                if set.isHold {
                    TextField("0", text: durationText(for: set.id))
                        .keyboardType(.numberPad)
                        .font(SharpitTypography.data)
                        .foregroundStyle(SharpitColor.foreground)
                        .focused($focusedField, equals: .duration(set.id))
                        .frame(minWidth: 44, maxWidth: 72, alignment: .leading)
                        .accessibilityLabel(set.durationUsesMinutes ? "Durée en minutes" : "Durée en secondes")
                    Button {
                        session.setUsesDuration(id: set.id, false)
                        focusedField = nil
                    } label: {
                        Text(set.durationUsesMinutes ? "min" : "s")
                            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .underline(pattern: .dot)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Passer en kilos")
                    .accessibilityHint("Affiche répétitions et charge")
                    Spacer(minLength: 0)
                } else {
                    TextField("0", text: repsText(for: set.id))
                        .keyboardType(.numberPad)
                        .font(SharpitTypography.data)
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .reps(set.id))
                        .frame(width: 44, alignment: .trailing)
                        .accessibilityLabel("Répétitions")

                    Text("×")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .padding(.leading, -SharpitSpacing.xs)
                        .padding(.trailing, SharpitSpacing.sm)

                    TextField("0", text: weightText(for: set.id))
                        .keyboardType(.decimalPad)
                        .font(SharpitTypography.data)
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .weight(set.id))
                        .frame(width: 72, alignment: .trailing)
                        .accessibilityLabel("Charge en kilogrammes")

                    Button {
                        session.setUsesDuration(id: set.id, true)
                        focusedField = nil
                    } label: {
                        Text("kg")
                            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .underline(pattern: .dot)
                            .padding(.leading, -SharpitSpacing.xs)
                            .padding(.trailing, 4)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Passer en durée")
                    .accessibilityHint("Affiche une durée en minutes")

                    Spacer(minLength: 0)
                }

                Button {
                    if set.isDone {
                        session.uncompleteSet(id: set.id)
                    } else {
                        completeSet(id: set.id)
                    }
                } label: {
                    SharpitCheckBox(isOn: set.isDone)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set.isDone ? "Série faite" : "Marquer la série")
            }
            .padding(.leading, SharpitSpacing.rowPaddingX)
            .padding(.trailing, SharpitSpacing.xs)
            .frame(minHeight: SharpitSpacing.rowHeight)
            .sharpitSurface(.row)
            .animation(SharpitMotion.reveal, value: set.isDone)
        }
    }

    // MARK: - Rest (image 2)

    private var restPage: some View {
        let last = lastCompletedSet
        let next = session.current
        return VStack(spacing: SharpitSpacing.lg) {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repos")
                        .font(SharpitTypography.cardTitle)
                        .tracking(SharpitTypography.cardTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    Text(restSubtitle(next: next))
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let remaining = restRemaining
                    let progress = restTotal > 0 ? Double(restTotal - remaining) / Double(restTotal) : 1
                    ZStack {
                        SharpitScoreRing(fraction: 1 - progress, lineWidth: 18)
                        VStack(spacing: SharpitSpacing.xxs) {
                            Text(PlannedSessionFormat.restClock(remaining))
                                .font(SharpitTypography.heroScore)
                                .tracking(SharpitTypography.heroScoreTracking)
                                .foregroundStyle(SharpitColor.foreground)
                                .contentTransition(.numericText())
                            Text("jusqu’à la prochaine série")
                                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
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
                    restLine("Dernière", last?.readoutLine)
                    Spacer(minLength: SharpitSpacing.sm)
                    restLine("Prochaine", next?.readoutLine)
                }

                HStack(spacing: SharpitSpacing.sm) {
                    SharpitPrimaryButton(title: "+15 s", style: .secondary) {
                        extendRest(by: 15)
                    }
                    SharpitPrimaryButton(
                        title: restPaused ? "Reprendre" : "Pause",
                        style: .accent,
                        trailingSymbol: restPaused ? "play.circle.fill" : "pause.circle.fill"
                    ) {
                        toggleRestPause()
                    }
                    SharpitPrimaryButton(title: "Passer", trailingSymbol: "forward.circle.fill") {
                        endRest()
                    }
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)

            Spacer(minLength: 0)
        }
        .padding(SharpitSpacing.pageInset)
    }

    /// « Dernière  102,5 kg × 8 »: the word muted, the set bold.
    private func restLine(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
            Text(label)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.mutedForeground)
            Text(value ?? "—")
                .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(SharpitTypography.cardTitle)
                        .tracking(SharpitTypography.cardTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("\(session.completedCount) série\(session.completedCount == 1 ? "" : "s") cochée\(session.completedCount == 1 ? "" : "s")")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }

                // Feedback first — the job of this screen — then the set list as context.
                feedbackPanel

                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    Text("Exercices")
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body))
                        .foregroundStyle(SharpitColor.mutedForeground)
                    SharpitInsetGroup {
                        ForEach(Array(session.exerciseGroups.enumerated()), id: \.element.id) { offset, group in
                            let volume = group.volumeKg(in: session.targets)
                            let done = group.doneCount(in: session.targets)
                            SharpitInsetRow(title: group.name) {
                                SharpitNumberChip(number: offset + 1)
                            } trailing: {
                                Text("\(done) série\(done == 1 ? "" : "s")")
                                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline, digits: true))
                                    .foregroundStyle(SharpitColor.mutedForeground)
                                if volume > 0 {
                                    volumeFigure(volume)
                                }
                            }
                        }
                    }
                }

                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }

                SharpitPrimaryButton(
                    title: session.completedCount == 0 ? "Fermer" : "Enregistrer la séance",
                    isBusy: isSaving
                ) {
                    Task { await save() }
                }
                .disabled(isSaving)
            }
            .padding(SharpitSpacing.cardPadding)
            .sharpitSurface(.panel)
            .padding(SharpitSpacing.pageInset)
        }
    }

    private var feedbackPanel: some View {
        // Flat: it sits inside the summary card.
        VStack(alignment: .leading, spacing: SharpitSpacing.md) {
            SharpitEyebrow("Comment c’était ?")
            rpePicker
            feelingPicker
        }
    }

    private var rpePicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Effort")
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body))
                    .foregroundStyle(SharpitColor.mutedForeground)
                Spacer()
                Text("RPE \(rpe.map(String.init) ?? "—")")
                    .font(SharpitTypography.system(size: 16, weight: .bold, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    .contentTransition(.numericText())
            }
            SharpitBarTrack(fraction: Double(rpe ?? 0) / 10)
                .frame(height: SharpitTokens.barThickness)
            // Full-width ticks — finger tracks 1:1 across the scale (Apple direct manipulation).
            GuidedRPEScale(value: $rpe)
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
                            .sharpitConcentricBackground(selected ? SharpitColor.chipSurface : Color.clear, minimum: SharpitRadius.small)
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
        guard session.targets.contains(where: { $0.id == id }) else { return }
        session.completeSet(id: id)
        SharpitHaptics.play(.notch(major: true))
        AudioServicesPlaySystemSound(1057)
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
        guard isResting, !restPaused else { return }
        guard let endsAt = restEndsAt, endsAt.timeIntervalSinceNow <= 0 else { return }
        finishRestCountdown()
    }

    private func finishRestCountdown() {
        guard isResting else { return }
        AudioServicesPlaySystemSound(1005)
        SharpitHaptics.play(.notch(major: true))
        endRest()
    }

    private func endRest() {
        stopRest()
        path = session.current.map { [.exercise($0.exerciseName)] } ?? []
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
        guard phase == .overview else { return }
        if isResting, !forceActive, restEndsAt != nil || restPaused { return }

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
                guard let set = session.targets.first(where: { $0.id == id }),
                      let sec = set.loggedDurationSec
                else { return "" }
                if set.durationUsesMinutes {
                    return "\(max(sec / 60, sec > 0 ? 1 : 0))"
                }
                return "\(sec)"
            },
            set: { text in
                durationDraft[id] = text
                guard let index = session.targets.firstIndex(where: { $0.id == id }) else { return }
                let digits = text.filter(\.isNumber)
                let usesMinutes = session.targets[index].durationUsesMinutes
                if let value = Int(digits) {
                    let sec = usesMinutes ? min(max(value, 0), 180) * 60 : min(max(value, 0), 3600)
                    session.targets[index].loggedDurationSec = sec
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

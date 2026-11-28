import AudioToolbox
import StoreKit
import SwiftUI
import UIKit

/// Creates the logged STRENGTH activity and links it back to the planned session.
struct GuidedStrengthFinishContext {
    let client: any ActivityMutating
    /// Nil for a session started on its own (Activité's « Séance libre »): nothing to link.
    var linker: (any PlannedSessionLinking)? = nil
    let tokenProvider: () async throws -> String
    /// Called once the activity exists (and the link was attempted).
    var onFinished: (String) -> Void = { _ in }
}

/// The same view used to log a session by hand: no clock, no rest, no heart rate — the sets are
/// entered as they would be live, then handed back to the form that holds the day and the time.
struct GuidedStrengthLogging {
    let tokenProvider: () async throws -> String
    let onLogged: ([StrengthExerciseDraft]) -> Void
}

/// Full-screen phone follow — Strong's overview → sets card → rest ring, in Sharpit tokens.
struct GuidedStrengthWorkoutView: View {
    @State private var session: GuidedStrengthSession
    /// Nil when the session is only being logged (`logging`).
    let finish: GuidedStrengthFinishContext?
    var logging: GuidedStrengthLogging?
    @State private var showingExercisePicker = false
    @State private var noteTarget: ExerciseNoteTarget?

    @Environment(\.dismiss) private var dismiss
    @Environment(ShellRouter.self) private var router: ShellRouter?
    /// When « Terminer » was tapped: the session's end, for its recap.
    @State private var endedAt: Date?
    @Environment(\.requestReview) private var requestReview
    /// Nil when shown on its own (the design gallery): then it is a plain cover.
    @Environment(GuidedWorkoutDock.self) private var dock: GuidedWorkoutDock?
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
        /// Saved: what was done, read back once, before the session leaves.
        case recap(activityId: String)
    }

    private enum Route: Hashable {
        case exercise(String)
        case rest
        /// A timed hold's countdown, both sides for a one-sided move.
        case hold(UUID)
        /// The exercise's sheet opened on « Évolution », from its card's foot.
        case evolution(String)
    }

    private var focusedExercise: String? {
        guard case let .exercise(name) = path.last else { return nil }
        return name
    }

    private var isResting: Bool { path.last == .rest }

    init(session: GuidedStrengthSession, finish: GuidedStrengthFinishContext?, logging: GuidedStrengthLogging? = nil) {
        _session = State(initialValue: session)
        self.finish = finish
        self.logging = logging
    }

    private var isLogging: Bool { logging != nil }
    private var tokenProvider: (() async throws -> String)? { finish?.tokenProvider ?? logging?.tokenProvider }

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
                case let .recap(activityId):
                    recapPage(activityId: activityId)
                        .transition(.opacity)
                }
            }
            .animation(SharpitMotion.reveal, value: phase)
            .cliniqueSheet(wash: .coach, height: 220)
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(for: Route.self) { route in
                Group {
                    switch route {
                    case let .exercise(name): exerciseGuide(name: name)
                    case .rest: restPage
                    case let .hold(id): holdPage(id: id)
                    case let .evolution(name): exerciseGuide(name: name, opening: .evolution)
                    }
                }
                .cliniqueSheet(wash: .coach, height: 220)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !isLogging {
                        ToolbarItem(placement: .principal) { sessionStatus }
                        if dock != nil {
                            ToolbarItem(placement: .primaryAction) { minimizeButton }
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .background(SharpitCanvasBackground())
        .sharpitRegularColumn()
        .sheet(isPresented: $showingHeartRatePicker) {
            GuidedHeartRatePickerSheet(monitor: heartRate)
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(library: StrengthLibraryStore.shared.exercises) { pick in
                SharpitMotion.run {
                    session.addExercise(name: pick.name, catalogId: pick.catalogId, note: pick.note, history: pick.history)
                }
            }
        }
        .sheet(item: $noteTarget) { target in
            ExerciseNoteSheet(
                name: target.name,
                initial: StrengthLibraryStore.shared.athleteNote(of: target.name) ?? ""
            ) { text in
                guard let tokenProvider else { return }
                try await StrengthLibraryStore.shared.saveNote(name: target.name, note: text, tokenProvider: tokenProvider)
            }
        }
        // What the athlete last lifted or held opens each set the plan leaves without a figure.
        .task {
            guard let tokenProvider else { return }
            session.applyHistory(await StrengthLibraryStore.shared.load(tokenProvider: tokenProvider))
        }
        .onAppear {
            guard !isLogging else { return }
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
        // « Réduire » stays one tap away, in the open; finishing and quitting are rarer and
        // one tap further, in « … » (a Menu, not a confirmationDialog: it opens from the button).
        // Saved, the session has nothing left to hide or to quit: the recap's own buttons close it.
        if !isRecap {
            if dock != nil, !isLogging {
                ToolbarItem(placement: .topBarLeading) { minimizeButton }
            }
            if phase == .overview, !isLogging {
                ToolbarItem(placement: .principal) { sessionStatus }
            }
            ToolbarItem(placement: .primaryAction) { moreMenu }
        }
    }

    private var moreMenu: some View {
        Menu {
            // Only on the session overview — never on a single exercise's sets.
            if phase == .overview, !isLogging {
                Button("Terminer la séance", systemImage: "checkmark.circle") {
                    stopTimers()
                    endedAt = .now
                    SharpitMotion.run { phase = .summary }
                }
                .disabled(session.completedCount == 0)
            }
            Section("Les séries cochées ne seront pas enregistrées") {
                // One word, so the line never wraps; the section says what is lost. The glyph is
                // drawn red itself: a menu renders a template image in its own tint.
                Button(role: .destructive) {
                    stopTimers()
                    close()
                } label: {
                    Label {
                        Text("Abandonner")
                    } icon: {
                        Image(uiImage: Self.abandonGlyph)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .disabled(isSaving)
        .accessibilityLabel("Plus d'actions")
    }

    private static let abandonGlyph: UIImage = {
        let symbol = UIImage(systemName: "xmark.circle") ?? UIImage()
        return symbol.withTintColor(UIColor(SharpitColor.destructive), renderingMode: .alwaysOriginal)
    }()

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
        return SharpitColor.slate
    }

    private var heartRateAccessibilityLabel: String {
        if let bpm = heartRate.bpm, heartRate.status == .connected {
            return String(localized: "Fréquence cardiaque \(bpm) battements par minute")
        }
        switch heartRate.status {
        case .scanning, .connecting: return String(localized: "Recherche du capteur cardiaque")
        case .unauthorized, .unavailable: return String(localized: "Capteur cardiaque indisponible")
        case .connected: return String(localized: "Capteur cardiaque connecté")
        default: return String(localized: "Connecter un capteur cardiaque")
        }
    }

    // MARK: - Overview (image 3)

    private var overviewPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title)
                        .font(SharpitTypography.system(size: 28, weight: .semibold, relativeTo: .title))
                        .tracking(-0.5)
                        .foregroundStyle(SharpitColor.foreground)
                        .accessibilityAddTraits(.isHeader)
                }

                // Each exercise a card holding its sets, done in place; its name opens its sheet.
                VStack(spacing: SharpitSpacing.sm) {
                    ForEach(Array(session.exerciseGroups.enumerated()), id: \.element.id) { offset, group in
                        exerciseCard(group: group, order: offset + 1)
                    }
                }

                // Outside the plan if need be: what was done on top is better noted than left out.
                SharpitDashedAddButton(title: String(localized: "Ajouter un exercice")) {
                    showingExercisePicker = true
                }

                if !session.targets.isEmpty {
                    SharpitProgressBar(
                        label: String(localized: "Séries faites"),
                        value: "\(session.completedCount) / \(session.targets.count)",
                        fraction: Double(session.completedCount) / Double(session.targets.count)
                    )
                }

                Button {
                    stopTimers()
                    if let logging {
                        logging.onLogged(session.activityExercises())
                        dismiss()
                    } else {
                        endedAt = .now
                        SharpitMotion.run { phase = .summary }
                    }
                } label: {
                    Text(GuidedStrengthReadout.finishTitle(done: session.completedCount, isLogging: isLogging))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                .disabled(session.completedCount == 0)
            }
            .padding(.horizontal, SharpitSpacing.pageInset)
            .padding(.vertical, SharpitSpacing.md)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("OK") { focusedField = nil }
            }
        }
    }

    /// An exercise as the session shows it: its picture and name (opening its sheet), how many
    /// sets and where it stands, then the sets themselves, typed and ticked in place, and at its
    /// foot « Évolution » and « Ajouter une série » (the athlete's call, 2026-11-28).
    private func exerciseCard(group: GuidedStrengthExerciseGroup, order: Int) -> some View {
        let done = group.doneCount(in: session.targets)
        let total = group.indices.count
        let setIds = group.indices.map { session.targets[$0].id }
        let usesDuration = group.indices.first.map { session.targets[$0].usesDuration } ?? false
        let hasHistory = tokenProvider != nil && StrengthLibraryStore.shared.history(of: group.name) != nil
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SharpitSpacing.sm) {
                NavigationLink(value: Route.exercise(group.name)) {
                    HStack(spacing: SharpitSpacing.sm) {
                        GuidedExerciseThumbView(
                            url: ExerciseMediaCatalog.thumbURL(catalogId: group.exerciseCatalogId, name: group.name),
                            size: 48
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                                .foregroundStyle(SharpitColor.foreground)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(GuidedStrengthReadout.setsLine(done: done, total: total))
                                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline, digits: true))
                                .foregroundStyle(SharpitColor.slate)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SharpitColor.slate)
                            .accessibilityHidden(true)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityLabel("\(group.name), exercice \(order), \(GuidedStrengthReadout.setsLine(done: done, total: total))")
                .accessibilityHint("Ouvre la fiche de l’exercice")

                Menu {
                    Button("Voir la fiche", systemImage: "doc.text") {
                        focusedField = nil
                        path.append(.exercise(group.name))
                    }
                    Button(
                        usesDuration ? String(localized: "Compter en répétitions") : String(localized: "Compter en durée"),
                        systemImage: usesDuration ? "number" : "timer"
                    ) {
                        focusedField = nil
                        // The sets still to do: a set done keeps what was logged.
                        let open = session.targets.filter { setIds.contains($0.id) && !$0.isDone }.map(\.id)
                        for id in open {
                            session.setUsesDuration(id: id, !usesDuration)
                        }
                    }
                    if let last = setIds.last, session.canRemoveSet(id: last) {
                        Button("Retirer la dernière série", systemImage: "minus.circle", role: .destructive) {
                            SharpitMotion.run { session.removeSet(id: last) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SharpitColor.foreground)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(SharpitColor.tile))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .accessibilityLabel("Actions sur \(group.name)")
            }

            VStack(spacing: 0) {
                ForEach(setIds, id: \.self) { id in
                    setRow(id: id)
                }
            }
            .padding(.top, SharpitSpacing.xs)

            CliniqueDivider()
                .padding(.top, SharpitSpacing.xs)
            HStack(spacing: 0) {
                if hasHistory {
                    Button {
                        focusedField = nil
                        path.append(.evolution(group.name))
                    } label: {
                        Label("Évolution", systemImage: "chart.line.uptrend.xyaxis")
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.sharpitPressable)
                    Rectangle()
                        .fill(SharpitColor.divider)
                        .frame(width: 1, height: 22)
                        .accessibilityHidden(true)
                }
                Button {
                    SharpitMotion.run { session.addSet(toExercise: group.name) }
                } label: {
                    Label("Ajouter une série", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.sharpitPressable)
            }
            .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
            .foregroundStyle(SharpitColor.foreground)
            .padding(.bottom, -SharpitSpacing.xs)
        }
        .cliniqueCard()
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
        .accessibilityLabel(volume > 0 ? "\(GuidedStrengthSetTarget.volumeFigure(volume)) kilogrammes" : String(localized: "Aucun volume"))
    }

    // MARK: - Exercise sheet

    private func exerciseGuide(name: String, opening tab: ExerciseGuidePage.Tab = .guide) -> some View {
        let group = session.exerciseGroups.first { $0.name == name }
        let volume = group?.volumeKg(in: session.targets) ?? 0
        let position = session.exerciseGroups.firstIndex { $0.name == name }
            .map { String(localized: "Exercice \($0 + 1) sur \(session.exerciseGroups.count)") }
        return ExerciseGuidePage(
            name: name,
            catalogId: group?.exerciseCatalogId,
            position: position,
            coachNotes: group?.notes,
            volume: volume > 0 ? "\(GuidedStrengthSetTarget.volumeFigure(volume)) kg" : nil,
            tokenProvider: tokenProvider,
            opening: tab,
            onEditNote: { noteTarget = ExerciseNoteTarget(name: name) }
        )
    }

    /// One set on its exercise's card: its number, then each figure in its own field with its unit
    /// written in — « 12 rép. », « 10 kg », or « 45 s » for a hold — and the tick. A hold has its ▶,
    /// which counts it down on its own page.
    @ViewBuilder
    private func setRow(id: UUID) -> some View {
        if let set = session.targets.first(where: { $0.id == id }) {
            HStack(spacing: SharpitSpacing.xs) {
                Text("\(set.setNumber)")
                    .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                    .foregroundStyle(set.isDone ? SharpitColor.slate : SharpitColor.foreground)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(SharpitColor.outline, lineWidth: 1))
                    .accessibilityLabel("Série \(set.setNumber)")

                if set.isHold {
                    setField(
                        text: durationText(for: set.id),
                        unit: (set.durationUsesMinutes ? String(localized: "min") : String(localized: "s")) + sideSuffix(set),
                        keyboard: .numberPad,
                        focus: .duration(set.id),
                        accessibility: set.durationUsesMinutes ? String(localized: "Durée en minutes") : String(localized: "Durée en secondes")
                    )
                    // Kept in place once the set is done, hidden: the row must not shift on a tick.
                    Button {
                        focusedField = nil
                        path.append(.hold(set.id))
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SharpitColor.foreground)
                            .frame(width: 36, height: 36)
                            .background(Circle().strokeBorder(SharpitColor.outline, lineWidth: 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(set.isDone ? 0 : 1)
                    .disabled(set.isDone)
                    .accessibilityHidden(set.isDone)
                    .accessibilityLabel(set.perSide ? String(localized: "Lancer le maintien, côté gauche puis droit") : String(localized: "Lancer le maintien"))
                } else {
                    // Each figure carries its unit: « 15 × 10 kg » left the first one unnamed, and a
                    // load typed there was stored as repetitions — then prescribed back by the coach.
                    setField(
                        text: repsText(for: set.id),
                        unit: String(localized: "rép.") + sideSuffix(set),
                        keyboard: .numberPad,
                        focus: .reps(set.id),
                        accessibility: String(localized: "Répétitions")
                    )
                    // No load prescribed: an empty field, not a « 0 » read as a weight.
                    setField(
                        text: weightText(for: set.id),
                        unit: String(localized: "kg"),
                        placeholder: "—",
                        keyboard: .decimalPad,
                        focus: .weight(set.id),
                        accessibility: String(localized: "Charge en kilogrammes")
                    )
                }

                Button {
                    focusedField = nil
                    if set.isDone {
                        session.uncompleteSet(id: set.id)
                    } else {
                        completeSet(id: set.id)
                    }
                } label: {
                    Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 28, weight: .regular))
                        .foregroundStyle(set.isDone ? SharpitColor.foreground : SharpitColor.outline)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(set.isDone ? String(localized: "Série faite") : String(localized: "Marquer la série"))
            }
            .frame(minHeight: 52)
            .animation(SharpitMotion.reveal, value: set.isDone)
        }
    }

    /// « /côté » after a unit when one set covers both sides.
    private func sideSuffix(_ set: GuidedStrengthSetTarget) -> String {
        set.perSide ? String(localized: "/côté") : ""
    }

    /// A figure typed in place, in a hairline capsule with its unit after it.
    private func setField(
        text: Binding<String>,
        unit: String,
        placeholder: String = "0",
        keyboard: UIKeyboardType,
        focus: FieldFocus,
        accessibility: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: focus)
                .accessibilityLabel(accessibility)
            Text(unit)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(1)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SharpitSpacing.sm)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(
            Capsule().strokeBorder(focusedField == focus ? SharpitColor.foreground : SharpitColor.outline, lineWidth: 1)
        )
        .contentShape(Capsule())
        .onTapGesture { focusedField = focus }
    }

    /// Out of sight, still running: the bar above the tabs brings it back.
    private var minimizeButton: some View {
        Button {
            focusedField = nil
            dock?.minimize()
        } label: {
            Image(systemName: "chevron.down")
        }
        .accessibilityLabel("Réduire la séance")
        .accessibilityHint("La séance continue ; la barre au-dessus des onglets la rouvre")
    }

    @ViewBuilder
    private func holdPage(id: UUID) -> some View {
        if let set = session.targets.first(where: { $0.id == id }) {
            GuidedHoldPage(
                exerciseName: set.exerciseName,
                clock: GuidedHoldClock(
                    durationSec: set.loggedDurationSec ?? set.targetDurationSec ?? GuidedHoldClock.fallbackSec,
                    perSide: set.perSide
                )
            ) {
                completeSet(id: id)
                if path.last == .hold(id) { path.removeLast() }
            }
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
                        .foregroundStyle(SharpitColor.slate)
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
                                .foregroundStyle(SharpitColor.slate)
                        }
                    }
                    .frame(width: 220, height: 220)
                    .frame(maxWidth: .infinity)
                    .onChange(of: remaining) { _, value in
                        if value <= 0 { syncRestIfExpired() }
                    }
                }

                HStack {
                    restLine(String(localized: "Dernière"), last?.readoutLine)
                    Spacer(minLength: SharpitSpacing.sm)
                    restLine(String(localized: "Prochaine"), next?.readoutLine)
                }

                HStack(spacing: SharpitSpacing.sm) {
                    SharpitPrimaryButton(title: "+15 s", style: .secondary) {
                        extendRest(by: 15)
                    }
                    SharpitPrimaryButton(
                        title: restPaused ? String(localized: "Reprendre") : String(localized: "Pause"),
                        style: .accent,
                        trailingSymbol: restPaused ? "play.circle.fill" : "pause.circle.fill"
                    ) {
                        toggleRestPause()
                    }
                    SharpitPrimaryButton(title: String(localized: "Passer"), trailingSymbol: "forward.circle.fill") {
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
                .foregroundStyle(SharpitColor.slate)
            Text(value ?? "—")
                .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func restSubtitle(next: GuidedStrengthSetTarget?) -> String {
        guard let next else { return String(localized: "Dernière série terminée") }
        return String(localized: "\(next.exerciseName) · série \(next.setNumber) sur \(next.setCount)")
    }

    private var lastCompletedSet: GuidedStrengthSetTarget? {
        session.targets.last(where: \.isDone)
    }

    // MARK: - Ressenti

    private var isRecap: Bool {
        if case .recap = phase { return true }
        return false
    }

    /// « Comment s’est passée la séance ? »: the effort on the app's scale, what that level means,
    /// the feeling, then the save docked. One question a page, nothing else around it.
    private var summaryPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                Text("Comment s'est passée la séance ?")
                    .font(SharpitTypography.system(size: 28, weight: .semibold, relativeTo: .title))
                    .tracking(-0.5)
                    .foregroundStyle(SharpitColor.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
                    CliniqueScale(
                        title: String(localized: "Effort perçu"),
                        values: Array(1...10),
                        selection: rpe,
                        word: SessionEffortReadout.word,
                        ends: (String(localized: "Très facile"), String(localized: "Maximal"))
                    ) { rpe = $0 }
                    // Reserved height: choosing a level never moves what is under it.
                    Text(GuidedStrengthReadout.effortMeaning(rpe) ?? " ")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                        .accessibilityHidden(rpe == nil)
                }

                feelingPicker

                if let failure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.signalRisk)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, SharpitSpacing.lg)
        }
        .safeAreaInset(edge: .bottom) {
            SharpitBareActions {
                SharpitPrimaryButton(
                    title: session.completedCount == 0 ? String(localized: "Fermer") : String(localized: "Enregistrer la séance"),
                    isBusy: isSaving
                ) {
                    Task { await save() }
                }
                .disabled(isSaving)
                // « Terminer » is not a one-way door: back to the sets, nothing lost.
                Button("Reprendre la séance") {
                    failure = nil
                    endedAt = nil
                    SharpitMotion.run { phase = .overview }
                }
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(SharpitColor.foreground)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(isSaving)
            }
        }
    }

    /// The feeling on the same kind of track as the effort, as the session's own sheet asks it.
    private var feelingPicker: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            CliniqueScale(
                title: String(localized: "Ressenti"),
                values: SessionFeeling.allCases.map(\.rawValue),
                selection: feeling?.rawValue,
                word: { SessionFeeling(rawValue: $0)?.storedValue },
                ends: (SessionFeeling.veryBad.storedValue, SessionFeeling.veryGood.storedValue)
            ) { raw in
                feeling = SessionFeeling(rawValue: raw)
            }
            // Reserve height so selecting doesn't jump the layout (CLS).
            Text(feeling?.hint ?? " ")
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(feeling == nil)
        }
    }

    // MARK: - Recap

    /// What was done, once it is saved: the seal, the session's name and when, its figures, then
    /// each exercise and its sets. « Voir l’activité » opens it in Activité; « Terminé » closes.
    private func recapPage(activityId: String) -> some View {
        let recap = GuidedStrengthRecap(session: session, endedAt: endedAt ?? .now)
        return ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.lg) {
                VStack(spacing: SharpitSpacing.sm) {
                    GuidedSessionSavedSeal()
                    Text(session.title)
                        .font(SharpitTypography.system(size: 28, weight: .semibold, relativeTo: .title))
                        .tracking(-0.5)
                        .foregroundStyle(SharpitColor.foreground)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(recap.when)
                        .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                }
                .frame(maxWidth: .infinity)

                recapFigures(recap)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Exercices")
                        .font(SharpitTypography.sectionTitle)
                        .tracking(SharpitTypography.sectionTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                        .padding(.bottom, SharpitSpacing.xs)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(recap.exercises) { exercise in
                        CliniqueDivider()
                        HStack(alignment: .top, spacing: SharpitSpacing.sm) {
                            GuidedExerciseThumbView(
                                url: ExerciseMediaCatalog.thumbURL(catalogId: exercise.catalogId, name: exercise.name),
                                size: 44
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body))
                                    .foregroundStyle(SharpitColor.foreground)
                                ForEach(Array(exercise.lines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline, digits: true))
                                        .foregroundStyle(SharpitColor.slate)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)
                        .accessibilityElement(children: .combine)
                    }
                    CliniqueDivider()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, SharpitSpacing.lg)
        }
        .safeAreaInset(edge: .bottom) {
            SharpitBareActions {
                HStack(spacing: SharpitSpacing.sm) {
                    if router != nil {
                        Button {
                            leaveRecap(activityId: activityId, opening: true)
                        } label: {
                            Text("Voir l’activité").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CliniqueButtonStyle(kind: .outline, isLarge: true))
                    }
                    Button {
                        leaveRecap(activityId: activityId, opening: false)
                    } label: {
                        Text("Terminé").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
                }
            }
        }
    }

    /// Two figures a row between hairlines, as a session's page reads them.
    private func recapFigures(_ recap: GuidedStrengthRecap) -> some View {
        var figures: [(String, String)] = [
            (String(localized: "Durée"), recap.duration),
            (String(localized: "Séries"), "\(recap.sets)"),
        ]
        if recap.reps > 0 { figures.append((String(localized: "Répétitions"), "\(recap.reps)")) }
        if recap.volumeKg > 0 {
            figures.append((String(localized: "Volume"), "\(GuidedStrengthSetTarget.volumeFigure(recap.volumeKg)) kg"))
        }
        if let rpe {
            let word = SessionEffortReadout.word(rpe).map { " · \($0)" } ?? ""
            figures.append((String(localized: "Effort"), "\(rpe)/10\(word)"))
        }
        let rows = stride(from: 0, to: figures.count, by: 2).map { Array(figures[$0..<min($0 + 2, figures.count)]) }
        return VStack(spacing: 0) {
            CliniqueDivider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: SharpitSpacing.md) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, figure in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(figure.0)
                                .font(SharpitTypography.meta)
                                .foregroundStyle(SharpitColor.slate)
                            Text(figure.1)
                                .font(SharpitTypography.system(size: 22, weight: .semibold, relativeTo: .title3, digits: true))
                                .foregroundStyle(SharpitColor.foreground)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                    if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
                }
                .padding(.vertical, 12)
                CliniqueDivider()
            }
        }
    }

    /// The screen behind is told now (its toast, its refresh), then the session leaves; « Voir
    /// l’activité » then opens the session in Activité.
    private func leaveRecap(activityId: String, opening: Bool) {
        finish?.onFinished(activityId)
        close()
        if opening { router?.openActivity(id: activityId) }
    }

    // MARK: - Actions

    private func completeSet(id: UUID) {
        guard session.targets.contains(where: { $0.id == id }) else { return }
        // The card closes into its line and the next set opens into the card, rather than swapping.
        SharpitMotion.run { session.completeSet(id: id) }
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
            nextSetLine: nextSet.map { String(localized: "série \($0.setNumber) · \($0.readoutLine)") } ?? ""
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
        path = []
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
        guard !isLogging else { return }
        guard phase == .overview else { return }
        if isResting, !forceActive, restEndsAt != nil || restPaused { return }

        let focus = focusedExercise
        let current = session.current
        let exercise = focus ?? current?.exerciseName ?? ""
        let detail: String = {
            if let current, current.exerciseName == exercise {
                return String(localized: "série \(current.setNumber) · \(current.readoutLine)")
            }
            if let focus,
               let group = session.exerciseGroups.first(where: { $0.name == focus }) {
                let done = group.doneCount(in: session.targets)
                return String(localized: "\(done)/\(group.indices.count) séries")
            }
            return String(localized: "\(session.completedCount) série\(session.completedCount == 1 ? "" : "s")")
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

    /// Saved or quit: off the dock when it runs there, else the cover closes.
    private func close() {
        if let dock, !isLogging { dock.end() } else { dismiss() }
    }

    private func save() async {
        if session.completedCount == 0 {
            close()
            return
        }
        isSaving = true
        failure = nil
        defer { isSaving = false }
        guard let finish else { return }
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
                try? await finish.linker?.link(sessionId: plannedId, activityId: activityId, token: token)
            }
            ReviewPrompt.askAfterWin(requestReview)
            // Mirrored into Apple Santé behind: the session is saved either way.
            let (title, start, end) = (session.title, session.startedAt, Date.now)
            Task { try? await HealthKitWriter().saveStrengthWorkout(activityId: activityId, title: title, start: start, end: end) }
            // The sets just saved are the next session's defaults.
            Task { await StrengthLibraryStore.shared.load(tokenProvider: finish.tokenProvider, fresh: true) }
            // The recap first; the screen behind is told when it closes (`leaveRecap`).
            SharpitMotion.run { phase = .recap(activityId: activityId) }
        } catch let SharpitAPIError.message(reason) {
            failure = reason
        } catch {
            failure = SharpitErrorGuidance.message(for: error, subject: String(localized: "La séance"))
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

/// « Séance enregistrée »: the recap's seal, arriving once with the page — the session is the win,
/// the seal says it is kept. No confetti: the app animates meaning only.
private struct GuidedSessionSavedSeal: View {
    @State private var shown = false

    var body: some View {
        CliniqueStatusPill(String(localized: "Séance enregistrée"), status: .good)
            .scaleEffect(shown ? 1 : 0.85)
            .opacity(shown ? 1 : 0)
            .onAppear { SharpitMotion.run(SharpitMotion.reveal) { shown = true } }
    }
}


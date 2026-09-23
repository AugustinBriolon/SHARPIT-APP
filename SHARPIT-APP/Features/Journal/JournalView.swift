import SwiftData
import SwiftUI

/// The day's journal: what the athlete did, took or felt, beside the numbers the
/// devices report on their own.
struct JournalView: View {
    @State private var store: JournalStore
    @State private var showsPrefs = false
    @State private var showsWellness = false
    @State private var showsCaffeine = false
    @State private var showsHydration = false
    @State private var showsInsights = false
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?

    private let wellness: any WellnessServing
    private let tokenProvider: () async throws -> String

    init(
        client: any JournalServing,
        wellness: any WellnessServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil
    ) {
        self.wellness = wellness
        self.tokenProvider = tokenProvider
        _store = State(
            initialValue: JournalStore(
                client: client,
                tokenProvider: tokenProvider,
                modelContext: modelContext
            )
        )
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SharpitCanvasBackground())
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsInsights = true
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SharpitColor.foreground)
                    }
                    .accessibilityLabel("Enseignements du journal")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsPrefs = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SharpitColor.foreground)
                    }
                    .disabled(store.phase == .loading)
                    .accessibilityLabel("Personnaliser le journal")
                }
            }
            .sheet(isPresented: $showsPrefs) {
                JournalPrefsDrawer(store: store)
            }
            .sheet(isPresented: $showsWellness) {
                MorningWellnessSheet(
                    client: wellness,
                    tokenProvider: tokenProvider,
                    trainingDayId: store.trainingDayId
                ) { label in
                    store.applyMoodLabel(label)
                }
            }
            .sheet(isPresented: $showsCaffeine) {
                CaffeineInputSheet(store: store)
            }
            .sheet(isPresented: $showsHydration) {
                HydrationInputSheet(store: store)
            }
            .sheet(isPresented: $showsInsights) {
                JournalInsightsSheet(store: store)
            }
            .task { await store.load() }
            .onDisappear {
                Task { await store.flushPendingSave() }
            }
            .onChange(of: store.saveFailure) { _, failure in
                if let failure {
                    toastCenter?.show(
                        failure,
                        symbol: "exclamationmark.triangle.fill",
                        tone: .error,
                        autoDismissAfter: 3.5
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            JournalLoadingRows()
        case .failed(let message):
            ContentUnavailableView {
                Label("Journal indisponible", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
        case .ready:
            entries
        }
    }

    private var entries: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                // Interactive week navigation strip
                JournalDatePicker(store: store)

                if store.hasNothingToShow {
                    ContentUnavailableView {
                        Label("Rien à suivre", systemImage: "book.closed")
                    } description: {
                        Text("Choisis ce que tu veux noter chaque jour.")
                    } actions: {
                        Button("Personnaliser") { showsPrefs = true }
                    }
                    .padding(.top, SharpitSpacing.xl)
                }

                // The web's order, top to bottom: the day's values, then the night that
                // ended this morning, then the day's own signals. Grouped by when a signal
                // happened rather than by what kind of thing it is — an athlete answers a
                // journal in the order they lived it.
                dayMetricsSection
                checklistSection
                priorNightSection
                daySignalsSection
            }
            .padding(SharpitSpacing.pageInset)
            .padding(.bottom, SharpitSpacing.section)
        }
    }

    /// Caféine, Humeur, Hydratation — values the athlete sets, not answers they give.
    @ViewBuilder
    private var dayMetricsSection: some View {
        let metrics = store.visibleTrackables.filter { $0.kind == .caffeine || $0.kind == .mood || $0.kind == .hydration }
        if !metrics.isEmpty {
            JournalSection(title: "Journée") {
                ForEach(metrics) { trackable in
                    JournalTrackableRow(
                        trackable: trackable,
                        store: store,
                        onOpenWellness: { showsWellness = true },
                        onOpenCaffeine: { showsCaffeine = true },
                        onOpenHydration: { showsHydration = true }
                    )
                }
            }
        }
    }

    /// What the devices reported, already decided server-side. Read-only: no toggle, no
    /// chevron and no pressable tile, because nothing here opens or changes (ADR 0004).
    @ViewBuilder
    private var checklistSection: some View {
        if !store.checklist.isEmpty {
            JournalSection(
                title: "Checklist auto",
                hint: "Dérivée de tes données santé et activités — lecture seule."
            ) {
                ForEach(store.checklist) { item in
                    JournalChecklistRow(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private var priorNightSection: some View {
        let trackables = store.priorNightTrackables
        if !trackables.isEmpty {
            JournalSection(title: "Nuit", hint: priorNightHint) {
                ForEach(trackables) { trackable in
                    JournalTrackableRow(trackable: trackable, store: store)
                }
            }
        }
    }

    private var priorNightHint: String {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: store.selectedDate) ?? store.selectedDate
        let start = yesterday.sharpitFormatted(.dateTime.day().month(.abbreviated))
        let end = store.selectedDate.sharpitFormatted(.dateTime.day().month(.abbreviated))
        return "\(start) → \(end)"
    }

    /// The day's own signals, with the athlete's own items after them — a trackable they
    /// wrote themselves has no window, so it belongs to the day.
    @ViewBuilder
    private var daySignalsSection: some View {
        let trackables = store.dayTrackables
        let custom = store.visibleCustomItems
        if !trackables.isEmpty || !custom.isEmpty {
            JournalSection(title: "Signaux du jour") {
                ForEach(trackables) { trackable in
                    JournalTrackableRow(trackable: trackable, store: store)
                }
                ForEach(custom) { item in
                    JournalCustomItemRow(item: item, store: store)
                }
            }
        }
    }
}

/// Rows in the shape the journal is about to show. The shared loading instrument
/// draws a verdict plate and gauges, which this screen never has.
private struct JournalLoadingRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Journée")
            ForEach(0..<5, id: \.self) { _ in
                RoundedRectangle(cornerRadius: SharpitSpacing.cardRadius)
                    .fill(SharpitColor.analysisSurface)
                    .frame(height: 64)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SharpitSpacing.pageInset)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Chargement du journal")
    }
}

private struct JournalSection<Content: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(title)
            if let hint {
                Text(hint)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JournalTrackableRow: View {
    let trackable: JournalTrackable
    @Bindable var store: JournalStore
    var onOpenWellness: () -> Void = {}
    var onOpenCaffeine: () -> Void = {}
    var onOpenHydration: () -> Void = {}

    var body: some View {
        switch trackable.kind {
        case .factor:
            JournalFactorRow(
                label: trackable.label,
                symbolName: trackable.symbolName,
                iconColor: trackable.category.color,
                state: store.entry.state(of: trackable.id)
            ) { newState in
                store.set(factorId: trackable.id, to: newState)
            }
            .equatable()
        case .caffeine:
            JournalMetricRow(
                label: trackable.label,
                symbolName: trackable.symbolName,
                iconColor: trackable.category.color,
                value: store.entry.caffeineMg.map { "\($0) mg" } ?? "— mg",
                onOpen: onOpenCaffeine
            )
        case .hydration:
            JournalMetricRow(
                label: trackable.label,
                symbolName: trackable.symbolName,
                iconColor: trackable.category.color,
                value: store.entry.hydrationMl.map { "\($0) ml" } ?? "— ml",
                onOpen: onOpenHydration
            )
        case .mood:
            JournalMetricRow(
                label: trackable.label,
                symbolName: trackable.symbolName,
                iconColor: trackable.category.color,
                value: store.moodLabel ?? "Non renseigné",
                onOpen: onOpenWellness
            )
        case .auto:
            // A derived line carries no answer, so it has no row here: the checklist section
            // renders it from the server's verdict instead.
            EmptyView()
        }
    }
}

private struct JournalCustomItemRow: View {
    let item: JournalCustomItem
    @Bindable var store: JournalStore

    var body: some View {
        JournalFactorRow(
            label: item.label,
            symbolName: JournalCatalogue.customSymbolName,
            iconColor: SharpitColor.primary,
            state: store.entry.state(of: item.id)
        ) { newState in
            store.set(factorId: item.id, to: newState)
        }
        .equatable()
    }
}

/// An interactive metric row (Caféine, Hydratation, Humeur) with formatted readout
/// and a forward action indicator opening dedicated input sheets.
private struct JournalMetricRow: View {
    let label: String
    let symbolName: String
    var iconColor: Color = SharpitColor.mutedForeground
    let value: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: symbolName)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(label)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)

                Spacer(minLength: SharpitSpacing.xs)

                Text(value)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(isUnset ? SharpitColor.mutedForeground : SharpitColor.primary)
                    .monospacedDigit()

                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .frame(width: 26, height: 26)
                    .background(SharpitColor.analysisGrid, in: RoundedRectangle(cornerRadius: 7))
                    .accessibilityHidden(true)
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(value)
    }

    private var isUnset: Bool {
        value.hasPrefix("—") || value.contains("non renseigné") || value.contains("Non renseigné")
    }
}

/// One derived line: whether the day met a threshold, and by how much.
private struct JournalChecklistRow: View {
    let item: V1JournalAutoChecklistItem

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: item.status.symbolName)
                .font(SharpitTypography.meta)
                .foregroundStyle(item.status.tone)
                .frame(width: 28, height: 28)
                .background(item.status.tone.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        // Italic for a line with nothing behind it, so a missing measure does
                        // not read as a measured zero.
                        .italic(item.status == .unavailable)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
    }
}

private extension JournalAutoStatus {
    var symbolName: String {
        switch self {
        case .done: "checkmark"
        case .missed: "minus"
        case .unavailable: "circle.dashed"
        }
    }

    /// Only a met threshold takes the brand tone. A missed one stays quiet: the athlete did
    /// not fail, they simply did not reach it, and the journal never scolds.
    var tone: Color {
        switch self {
        case .done: SharpitColor.primary
        case .missed, .unavailable: SharpitColor.mutedForeground
        }
    }
}

/// A yes / no / unanswered signal. Unanswered is its own answer — the analyses only
/// weigh what the athlete actually said — so it stays a visible third choice.
private struct JournalFactorRow: View, Equatable {
    let label: String
    let symbolName: String
    var iconColor: Color = SharpitColor.mutedForeground
    let state: JournalFactorState
    let onChange: (JournalFactorState) -> Void

    static func == (lhs: JournalFactorRow, rhs: JournalFactorRow) -> Bool {
        lhs.label == rhs.label &&
        lhs.symbolName == rhs.symbolName &&
        lhs.iconColor == rhs.iconColor &&
        lhs.state == rhs.state
    }

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            Image(systemName: symbolName)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(iconColor)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text(label)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: SharpitSpacing.xs)

            JournalAnswerToggle(state: state, onChange: onChange)
                .equatable()
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

private extension JournalFactorState {
    var symbolName: String {
        switch self {
        case .no: "xmark"
        case .unset: "minus"
        case .yes: "checkmark"
        }
    }

    var title: String {
        switch self {
        case .no: "Non"
        case .unset: "—"
        case .yes: "Oui"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .no: "Non"
        case .unset: "Non renseigné"
        case .yes: "Oui"
        }
    }

    /// The selection pill follows the answer: a recorded "non" reads red, an unanswered
    /// day stays quiet, a recorded "oui" is what the day now carries.
    var tone: Color {
        switch self {
        case .no: SharpitColor.signalRisk
        case .unset: SharpitElevatedColor.control
        case .yes: SharpitColor.primary
        }
    }

    var onTone: Color {
        switch self {
        case .no: .white
        case .unset: SharpitColor.foreground
        case .yes: SharpitColor.primaryForeground
        }
    }
}

/// Non, unanswered, Oui — in that order. Unanswered is a real third choice and not the
/// absence of one: the analyses only weigh an explicit answer, so an athlete has to be
/// able to go back to "not said".
///
/// Designed in accordance with Apple Human Interface Guidelines:
/// - Rigid outer frame (136x44pt) with strictly locked layout geometry so vertical jumps/repositions never occur.
/// - Full 44x44pt touch area per segment with zero horizontal overlap between adjacent options.
/// - Purely horizontal pill slide animated exclusively along the X axis with `SharpitMotion.selection`.
/// - Single synchronized animation state to eliminate animation conflicts during rapid option taps.
private struct JournalAnswerToggle: View, Equatable {
    let state: JournalFactorState
    let onChange: (JournalFactorState) -> Void

    static func == (lhs: JournalAnswerToggle, rhs: JournalAnswerToggle) -> Bool {
        lhs.state == rhs.state
    }

    private static let order: [JournalFactorState] = [.no, .unset, .yes]
    private static let segmentWidth: CGFloat = 44
    private static let segmentHeight: CGFloat = 30
    private static let inset: CGFloat = 2
    private static let trackWidth: CGFloat = (segmentWidth * 3) + (inset * 2) // 136 pt
    private static let trackHeight: CGFloat = segmentHeight + (inset * 2) // 34 pt

    private var selectedIndex: Int {
        Self.order.firstIndex(of: state) ?? 1
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // 1. Static track background (never moves, strictly centered vertically)
            Capsule()
                .fill(SharpitColor.analysisGrid)
                .frame(width: Self.trackWidth, height: Self.trackHeight)

            // 2. Sliding indicator pill (strictly horizontal offset, centered vertically)
            Capsule()
                .fill(state.tone)
                .sharpitShadow(.control)
                .frame(width: Self.segmentWidth, height: Self.segmentHeight)
                .offset(x: Self.inset + CGFloat(selectedIndex) * Self.segmentWidth)
                .animation(SharpitMotion.selection, value: state)

            // 3. Touch buttons aligned over each segment (44x44pt touch area for HIG)
            HStack(spacing: 0) {
                ForEach(Self.order, id: \.self) { value in
                    segmentButton(value)
                }
            }
            .padding(.horizontal, Self.inset)
        }
        .frame(width: Self.trackWidth, height: SharpitSpacing.minimumTouchTarget)
        .contentShape(Rectangle())
    }

    private func segmentButton(_ value: JournalFactorState) -> some View {
        let isSelected = state == value
        return Button {
            onChange(value)
        } label: {
            Image(systemName: value.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? value.onTone : SharpitColor.mutedForeground)
                .frame(width: Self.segmentWidth, height: Self.segmentHeight)
                .animation(SharpitMotion.selection, value: isSelected)
        }
        .buttonStyle(.plain)
        .frame(width: Self.segmentWidth, height: SharpitSpacing.minimumTouchTarget)
        .contentShape(Rectangle())
        .accessibilityLabel(value.accessibilityTitle)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

private struct JournalDatePicker: View {
    @Bindable var store: JournalStore
    private let weeks = SharpitWeeks(offsets: -26...0)
    @State private var weekOffset: Int
    @State private var showingCalendar = false

    init(store: JournalStore) {
        self.store = store
        _weekOffset = State(initialValue: weeks.offset(forWeekContaining: store.selectedDate))
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(store.selectedDate)
    }

    var body: some View {
        VStack(spacing: SharpitSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
                Button {
                    showingCalendar = true
                } label: {
                    HStack(spacing: SharpitSpacing.xxs) {
                        Text(store.selectedDate.sharpitFormatted(.dateTime.weekday(.wide).day().month(.abbreviated)).capitalizedFirst)
                            .font(SharpitTypography.verdict)
                            .tracking(SharpitTypography.verdictTracking)
                            .foregroundStyle(SharpitColor.foreground)
                            .contentTransition(.opacity)
                        Image(systemName: "chevron.down")
                            .font(SharpitTypography.label)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .accessibilityHidden(true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre le calendrier")

                Spacer(minLength: 0)

                if !isToday {
                    Button("Aujourd'hui") {
                        pick(.now)
                    }
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.primary)
                }
            }

            SharpitWeekStrip(weekOffset: $weekOffset, weeks: weeks) { day in
                let isFuture = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: .now)
                let isCompleted = store.isDayCompleted(date: day)
                Button {
                    pick(day)
                } label: {
                    SharpitStripDay(day: day, emphasis: emphasis(for: day, isFuture: isFuture)) {
                        JournalDayMark(isCompleted: isFuture ? nil : isCompleted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
                .accessibilityLabel(accessibilityLabel(for: day, isFuture: isFuture, isCompleted: isCompleted))
                .accessibilityAddTraits(Calendar.current.isDate(day, inSameDayAs: store.selectedDate) ? [.isButton, .isSelected] : .isButton)
            }
        }
        .sheet(isPresented: $showingCalendar) {
            SharpitCalendarSheet(
                title: "Journal",
                initial: store.selectedDate,
                weeks: weeks,
                range: weeks.selectableDates.lowerBound...Date.now,
                onPick: pick,
                onToday: { pick(.now) }
            )
        }
        .onChange(of: store.selectedDate) { _, newDate in
            let targetOffset = weeks.offset(forWeekContaining: newDate)
            if weekOffset != targetOffset {
                weekOffset = targetOffset
            }
        }
    }

    private func emphasis(for day: Date, isFuture: Bool) -> SharpitStripDay<JournalDayMark>.Emphasis {
        if isFuture { return .unavailable }
        if Calendar.current.isDate(day, inSameDayAs: store.selectedDate) { return .filled }
        if Calendar.current.isDateInToday(day) { return .accent }
        return .plain
    }

    private func accessibilityLabel(for day: Date, isFuture: Bool, isCompleted: Bool) -> String {
        let date = day.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide))
        if isFuture { return "\(date), non disponible" }
        return isCompleted ? "\(date), journal complété" : "\(date), journal incomplet"
    }

    private func pick(_ day: Date) {
        SharpitHaptics.play(.light)
        weekOffset = weeks.offset(forWeekContaining: day)
        Task {
            await store.selectDate(day)
        }
    }
}

private struct JournalDayMark: View {
    let isCompleted: Bool?

    var body: some View {
        switch isCompleted {
        case true?:
            Circle().fill(SharpitColor.primary)
        case false?:
            Circle().strokeBorder(SharpitColor.mutedForeground.opacity(0.4), lineWidth: 1)
        case nil:
            Color.clear
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}


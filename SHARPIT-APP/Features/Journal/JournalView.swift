import SwiftData
import SwiftUI

/// The day's journal: what the athlete did, took or felt, beside the numbers the
/// devices report on their own.
struct JournalView: View {
    @State private var store: JournalStore
    /// Nil when the client cannot read the analyses (a test stub): the toolbar then omits them.
    @State private var analysesStore: JournalAnalysesStore?
    @State private var showsPrefs = false
    @State private var showsWellness = false
    @State private var showsCaffeine = false
    @State private var showsHydration = false
    @State private var showsDriving = false
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @Environment(ShellRouter.self) private var router: ShellRouter?

    private let wellness: any WellnessServing
    private let tokenProvider: () async throws -> String

    init(
        client: any JournalServing,
        wellness: any WellnessServing,
        tokenProvider: @escaping () async throws -> String,
        modelContext: ModelContext? = nil,
        dataDaysClient: any DataDaysServing = SharpitClient()
    ) {
        self.wellness = wellness
        self.tokenProvider = tokenProvider
        _analysesStore = State(
            initialValue: (client as? any JournalAnalysesServing).map {
                JournalAnalysesStore(client: $0, tokenProvider: tokenProvider)
            }
        )
        _store = State(
            initialValue: JournalStore(
                client: client,
                tokenProvider: tokenProvider,
                modelContext: modelContext,
                journalDays: { try await dataDaysClient.dataDays(domain: .journal, from: $0, to: $1, token: $2) },
                checkinMood: { dayId, token in
                    try await wellness.wellnessCheckin(trainingDayId: dayId, token: token).entry
                        .flatMap { WellnessScore(rawValue: $0.mood) }
                        .map { WellnessDimension.mood.label(for: $0) }
                }
            )
        )
    }

    var body: some View {
        entries
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .cliniqueSheet(wash: .coach, height: 240)
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.inline)
            // The bar carries the way back and the signals' choice; the name opens the page.
            .toolbar {
                ToolbarItem(placement: .principal) { Text("") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Choisir mes signaux") { showsPrefs = true }
                        .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                        .foregroundStyle(SharpitColor.foreground)
                        .disabled(store.phase == .loading)
                }
            }
            .cliniqueReturnButton()
            .sheet(isPresented: $showsPrefs) {
                JournalPrefsDrawer(store: store)
            }
            .sheet(isPresented: $showsWellness) {
                MorningWellnessSheet(
                    client: wellness,
                    tokenProvider: tokenProvider,
                    trainingDayId: store.trainingDayId,
                    onSaved: { router?.noteMorningCheckIn() }
                ) { label in
                    store.applyMoodLabel(label)
                }
            }
            .sheet(isPresented: $showsCaffeine) {
                CaffeineInputSheet(store: store)
            }
            .sheet(isPresented: $showsDriving) {
                DrivingInputSheet(store: store)
            }
            .sheet(isPresented: $showsHydration) {
                HydrationInputSheet(store: store)
            }
            .task { await store.load() }
            .task { await store.markAnsweredDays() }
            .task { await analysesStore?.load() }
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

    /// The header stays whatever the day's state: a day that failed to load is still one swipe
    /// or one tap away from another.
    private var entries: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                JournalHeader(store: store, progress: store.phase == .ready && !store.isReadingDay ? progress : nil)
                    .padding(.bottom, 14)
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
                    .padding(.top, SharpitSpacing.xl)
                case .ready:
                    if store.hasNothingToShow {
                        ContentUnavailableView {
                            Label("Rien à suivre", systemImage: "book.closed")
                        } description: {
                            Text("Choisis ce que tu veux noter chaque jour.")
                        } actions: {
                            Button("Choisir mes signaux") { showsPrefs = true }
                        }
                        .padding(.top, SharpitSpacing.xl)
                    }
                    dayLines(pending: store.isReadingDay)
                    insight
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, SharpitSpacing.xs)
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDisabled(store.phase == .loading)
        .daySwipe(day: store.selectedDate) { day in Task { await store.selectDate(day) } } neighbor: { _ in
            // The day beside: once the preferences are known, its own lines with their values
            // pending — only the very first read draws the whole skeleton.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    JournalHeader(store: store, progress: nil).padding(.bottom, 14)
                    if store.hasReadPrefs {
                        dayLines(pending: true)
                    } else {
                        JournalLoadingRows()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, SharpitSpacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDisabled(true)
        }
    }

    /// The signals that take an answer, and how many carry one: « 3 signaux sur 5 notés ».
    private var progress: String? {
        let entry = store.entry
        var noted = 0, total = 0
        for trackable in store.visibleTrackables {
            switch trackable.kind {
            case .factor: total += 1; noted += entry.state(of: trackable.id) == .unset ? 0 : 1
            case .caffeine: total += 1; noted += (entry.caffeineMg ?? 0) > 0 ? 1 : 0
            case .hydration: total += 1; noted += (entry.hydrationMl ?? 0) > 0 ? 1 : 0
            case .driving: total += 1; noted += (entry.drivingMinutes ?? 0) > 0 ? 1 : 0
            case .mood: total += 1; noted += store.moodLabel == nil ? 0 : 1
            case .auto, .diet: break
            }
        }
        for item in store.visibleCustomItems {
            total += 1
            noted += entry.state(of: item.id) == .unset ? 0 : 1
        }
        return JournalReadout.progress(noted: noted, of: total)
    }

    /// The day in the order it was lived, a titled group each: the day's values, what the
    /// devices measured, the night that ended this morning, then the day's own signals.
    /// `pending`: the lines are known, the day's answers are not — values redacted, nothing
    /// tappable, and none of the shown day's own lines (the checklist) carried over.
    private func dayLines(pending: Bool) -> some View {
        let metrics = store.visibleTrackables.filter { $0.kind == .mood }
            + store.visibleTrackables.filter { [.caffeine, .hydration, .driving].contains($0.kind) }
        return VStack(alignment: .leading, spacing: 26) {
            if !metrics.isEmpty {
                JournalGroup(title: String(localized: "Journée"), hue: SharpitColor.pillarNutrition) {
                    ForEach(metrics) { trackable in metricLine(trackable) }
                }
            }
            if !pending, !store.checklist.isEmpty {
                JournalGroup(title: String(localized: "Mesuré pour toi"), hint: String(localized: "Lu de tes données. Rien à noter."), hue: SharpitColor.pillarRecovery) {
                    ForEach(store.checklist) { item in JournalChecklistLine(item: item) }
                }
            }
            if !store.priorNightTrackables.isEmpty {
                JournalGroup(title: String(localized: "Nuit dernière"), hue: SharpitColor.pillarSleep) {
                    ForEach(store.priorNightTrackables) { trackable in
                        factorLine(id: trackable.id, label: trackable.label, symbol: trackable.symbolName, pending: pending)
                    }
                }
            }
            if !store.dayTrackables.isEmpty || !store.visibleCustomItems.isEmpty {
                JournalGroup(title: String(localized: "Signaux du jour"), hue: SharpitColor.pillarCoach) {
                    ForEach(store.dayTrackables) { trackable in
                        factorLine(id: trackable.id, label: trackable.label, symbol: trackable.symbolName, pending: pending)
                    }
                    ForEach(store.visibleCustomItems) { item in
                        factorLine(id: item.id, label: item.label, symbol: "pencil.line", pending: pending)
                    }
                }
            }
        }
        .redacted(reason: pending ? .placeholder : [])
        .allowsHitTesting(!pending)
    }

    private func factorLine(id: String, label: String, symbol: String, pending: Bool) -> some View {
        JournalFactorLine(label: label, symbol: symbol, state: pending ? .unset : store.entry.state(of: id)) {
            store.set(factorId: id, to: $0)
        }
    }

    @ViewBuilder
    private func metricLine(_ trackable: JournalTrackable) -> some View {
        switch trackable.kind {
        case .mood:
            JournalLine(title: trackable.label, symbol: trackable.symbolName, detail: String(localized: "Lu de ton ressenti du matin"), onOpen: { showsWellness = true }) {
                if let mood = store.moodLabel {
                    JournalValuePill(text: mood)
                } else {
                    JournalCapsule(text: JournalReadout.answer(.unset), style: .outline)
                }
            }
        case .caffeine:
            JournalLine(title: trackable.label, symbol: trackable.symbolName, detail: String(localized: "Un café ≈ 80 mg"), onOpen: { showsCaffeine = true }) {
                JournalStepper(
                    value: store.entry.caffeineMg.map { "\($0) mg" } ?? "— mg",
                    label: trackable.label,
                    onLess: { store.adjustCaffeine(by: -80) },
                    onMore: { store.adjustCaffeine(by: 80) }
                )
            }
        case .hydration:
            JournalLine(title: trackable.label, symbol: trackable.symbolName, detail: JournalReadout.litres(store.entry.hydrationMl), onOpen: { showsHydration = true }) {
                Button { store.adjustHydration(by: 250) } label: {
                    JournalCapsule(text: "+ 25 cl", style: .outline)
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityLabel("Ajouter 25 centilitres")
            }
        case .driving:
            JournalLine(title: trackable.label, symbol: trackable.symbolName, detail: String(localized: "Par quarts d'heure"), onOpen: { showsDriving = true }) {
                if (store.entry.drivingMinutes ?? 0) == 0 {
                    JournalCapsule(text: JournalReadout.answer(.unset), style: .outline)
                } else {
                    JournalValuePill(text: JournalDrivingFormat.minutes(store.entry.drivingMinutes))
                }
            }
        case .factor, .auto, .diet:
            // A derived line or a standing diet carries no value, so it has no line here.
            EmptyView()
        }
    }

    /// « Ce que ton journal montre »: the analyses' one sentence, and the way to all of them.
    @ViewBuilder
    private var insight: some View {
        if let analysesStore, let analyses = analysesStore.analyses {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Ce que ton journal montre")
                        .font(SharpitTypography.sectionTitle)
                        .tracking(SharpitTypography.sectionTitleTracking)
                        .foregroundStyle(SharpitColor.foreground)
                    Spacer(minLength: SharpitSpacing.xs)
                    Text("Tout voir")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.foreground)
                }
                HStack(alignment: .center, spacing: 14) {
                    HStack(alignment: .bottom, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(SharpitColor.pillarSleep.opacity(0.25)).frame(width: 15, height: 26)
                        RoundedRectangle(cornerRadius: 4).fill(SharpitColor.pillarNutrition).frame(width: 15, height: 15)
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(analyses.reading?.headline ?? String(localized: "Pas encore assez de jours notés"))
                            .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                            .foregroundStyle(SharpitColor.foreground)
                        Text(analyses.reading?.verdict ?? JournalAnalysesReadout.progress(analyses))
                            .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote, digits: true))
                            .foregroundStyle(SharpitColor.slate)
                    }
                    .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .cliniqueCard()
            }
            .padding(.top, 26)
            .overlay {
                NavigationLink { JournalAnalysesView(store: analysesStore) } label: { Color.clear.contentShape(.rect) }
                    .accessibilityLabel("Analyses du journal")
            }
        }
    }
}

/// How the journal words what the server sends as numbers and states.
nonisolated enum JournalReadout {
    /// « 3 signaux sur 5 notés »; nil when nothing takes an answer.
    static func progress(noted: Int, of total: Int) -> String? {
        guard total > 0 else { return nil }
        return total == 1
            ? String(localized: "\(noted) signal sur 1 noté")
            : String(localized: "\(noted) signaux sur \(total) notés")
    }

    /// « 1,2 L »; nil while nothing was drunk or noted.
    static func litres(_ millilitres: Int?, locale: Locale = .current) -> String? {
        guard let millilitres, millilitres > 0 else { return nil }
        return (Double(millilitres) / 1_000).formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + " L"
    }

    /// The answer a tap leaves: the one tapped, or none when it was already given.
    static func tapped(_ answer: JournalFactorState, from current: JournalFactorState) -> JournalFactorState {
        current == answer ? .unset : answer
    }

    /// Unanswered is a real third answer, said « À noter ».
    static func answer(_ state: JournalFactorState) -> String {
        switch state {
        case .unset: String(localized: "À noter")
        case .yes: String(localized: "Oui")
        case .no: String(localized: "Non")
        }
    }
}

/// « Journal », then the day it shows and how much of it is noted. The day opens the calendar.
private struct JournalHeader: View {
    @Bindable var store: JournalStore
    let progress: String?
    private let weeks = SharpitWeeks(offsets: SharpitWeeks.history)
    @State private var showingCalendar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Journal")
                .font(SharpitTypography.system(size: 32, weight: .semibold, relativeTo: .largeTitle))
                .tracking(-0.6)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Button { showingCalendar = true } label: {
                Text([store.selectedDate.sharpitFormatted(.dateTime.weekday(.wide).day().month(.wide)).capitalizedFirst, progress].compactMap(\.self).joined(separator: " · "))
                    .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .callout, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .multilineTextAlignment(.leading)
                    .contentTransition(.numericText())
                    .animation(SharpitMotion.selection, value: store.selectedDate)
            }
            .buttonStyle(.sharpitPressable)
            .accessibilityHint("Ouvre le calendrier")
        }
        .sheet(isPresented: $showingCalendar) {
            SharpitCalendarSheet(
                title: String(localized: "Journal"),
                initial: store.selectedDate,
                weeks: weeks,
                range: weeks.selectableDates.lowerBound...Date.now,
                marks: calendarMarks,
                legend: [(.filled, String(localized: "Journal rempli")), (.muted, String(localized: "Rien de noté"))],
                onPick: { day in Task { await store.selectDate(day) } },
                onToday: { Task { await store.selectDate(.now) } }
            )
        }
    }

    /// Every day the calendar shows: filled where something was noted, muted where the day was
    /// read and holds nothing, nothing while unknown.
    private var calendarMarks: [Date: SharpitCalendarMark] {
        let calendar = weeks.calendar
        let today = calendar.startOfDay(for: .now)
        var marks: [Date: SharpitCalendarMark] = [:]
        var day = calendar.startOfDay(for: weeks.selectableDates.lowerBound)
        while day <= today {
            switch store.hasAnswer(on: day) {
            case true?: marks[day] = .filled
            case false?: marks[day] = .muted
            case nil: break
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return marks
    }
}

/// The journal's own lines, redacted, in the shape it is about to show.
private struct JournalLoadingRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            JournalGroup(title: String(localized: "Journée")) {
                JournalLine(title: String(localized: "Humeur"), symbol: "face.smiling", detail: String(localized: "Lu de ton ressenti du matin")) {
                    JournalCapsule(text: JournalReadout.answer(.unset), style: .outline)
                }
            }
            JournalGroup(title: String(localized: "Signaux du jour")) {
                ForEach([String(localized: "Alcool"), String(localized: "Écrans tard"), String(localized: "Sieste")], id: \.self) { label in
                    JournalFactorLine(label: label, symbol: "circle", state: .unset) { _ in }
                }
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement du journal")
    }
}

/// A titled group of the analyses' cards.
struct JournalSection<Content: View>: View {
    let title: String
    var hint: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow(title)
            if let hint {
                Text(hint)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The journal's lines as one table on the sheet: a hairline above each, none after the last.
struct JournalLines<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    CliniqueDivider()
                    row
                }
            }
        }
    }
}

/// A titled group of the day's lines: when they happened, then the lines under hairlines.
struct JournalGroup<Content: View>: View {
    let title: String
    var hint: String? = nil
    var hue: Color? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            if let hint {
                Text(hint)
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(SharpitColor.slate)
                    .padding(.top, 2)
            }
            JournalLines { content }
                .padding(.top, 8)
                .environment(\.journalHue, hue)
        }
    }
}

/// A row's glyph in the signals' drawer and the check-in: ink on the chip tone.
struct JournalRowIcon: View {
    static let tile: CGFloat = 32
    let symbolName: String
    /// The group's hue, as a glyph on its own faint wash — a mark, never the line's text.
    var hue: Color? = nil

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(hue ?? SharpitColor.foreground)
            .frame(width: Self.tile, height: Self.tile)
            .sharpitConcentricBackground(hue?.opacity(0.14) ?? SharpitColor.tile, minimum: 9)
            .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    /// The hue a journal group lends its lines' glyphs.
    @Entry var journalHue: Color? = nil
}

/// A journal line: a name over what it holds, its control at the trailing edge. The words open
/// the line's own sheet when it has one.
struct JournalLine<Control: View>: View {
    let title: String
    /// The line's glyph, on a quiet tile: the signals are told apart before they are read.
    var symbol: String? = nil
    var detail: String? = nil
    var onOpen: (() -> Void)? = nil
    @ViewBuilder let control: Control
    @Environment(\.journalHue) private var hue

    var body: some View {
        HStack(alignment: .center, spacing: SharpitSpacing.sm) {
            if let symbol { JournalRowIcon(symbolName: symbol, hue: hue) }
            if let onOpen {
                Button(action: onOpen) { words.contentShape(.rect) }
                    .buttonStyle(.sharpitPressable)
            } else {
                words
            }
            control
        }
        .padding(.vertical, 10)
        .frame(minHeight: 60)
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                .foregroundStyle(SharpitColor.foreground)
            if let detail {
                Text(detail)
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .footnote, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A line's answer as a capsule: an outline while it waits, ink for « oui », a quiet fill for « non ».
struct JournalCapsule: View {
    enum Style { case outline, ink, quiet }
    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(SharpitTypography.system(size: 16, weight: style == .outline ? .regular : .semibold, relativeTo: .callout, digits: true))
            .foregroundStyle(style == .ink ? SharpitColor.primaryForeground : SharpitColor.foreground)
            .padding(.horizontal, 18)
            .frame(minWidth: 72, minHeight: 44)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(SharpitColor.divider, lineWidth: style == .outline ? 1 : 0))
            .contentShape(Capsule())
    }

    private var fill: Color {
        switch style {
        case .outline: .clear
        case .ink: SharpitColor.primary
        case .quiet: SharpitColor.tile
        }
    }
}

/// A value read elsewhere, said in a small pill (« Moyen », « 45 min »).
struct JournalValuePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote, digits: true))
            .foregroundStyle(SharpitColor.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(SharpitColor.tile, in: Capsule())
    }
}

/// « − 160 mg + »: a value stepped in place.
struct JournalStepper: View {
    let value: String
    let label: String
    let onLess: () -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            step("minus", String(localized: "Moins"), onLess)
            Text(value)
                .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                .contentTransition(.numericText())
                .frame(minWidth: 62)
            step("plus", String(localized: "Plus"), onMore)
        }
        .padding(.horizontal, 4)
        .background(SharpitColor.tile, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func step(_ symbol: String, _ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 40, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityLabel(name)
    }
}

/// One derived line: whether the day met a threshold, and by how much. Read-only.
private struct JournalChecklistLine: View {
    let item: V1JournalAutoChecklistItem

    var body: some View {
        JournalLine(title: item.label, symbol: "waveform.path.ecg", detail: item.detail?.isEmpty == false ? item.detail : nil) {
            Image(systemName: item.status == .done ? "checkmark.circle" : item.status == .missed ? "minus.circle" : "circle.dashed")
                .font(.system(size: 22, weight: .regular))
                // Only a met threshold takes a tone: a missed one stays quiet, the journal never scolds.
                .foregroundStyle(item.status == .done ? SharpitColor.pillarRecovery : SharpitColor.slate.opacity(0.6))
                .accessibilityLabel(item.status == .done ? String(localized: "Atteint") : item.status == .missed ? String(localized: "Pas atteint") : String(localized: "Pas de mesure"))
        }
        .accessibilityElement(children: .combine)
    }
}

/// A yes / no / unanswered signal. Both answers are on the line: a tap gives one, a second tap
/// on it takes it back — unanswered is its own answer, since the analyses only weigh what the
/// athlete actually said.
struct JournalFactorLine: View {
    let label: String
    var symbol: String? = nil
    let state: JournalFactorState
    let onChange: (JournalFactorState) -> Void

    var body: some View {
        JournalLine(title: label, symbol: symbol) {
            HStack(spacing: 2) {
                answer(.no)
                answer(.yes)
            }
            .padding(3)
            .background(SharpitColor.tile, in: Capsule())
            .animation(SharpitMotion.selection, value: state)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
            .accessibilityValue(JournalReadout.answer(state))
        }
    }

    private func answer(_ value: JournalFactorState) -> some View {
        let isChosen = state == value
        return Button { onChange(JournalReadout.tapped(value, from: state)) } label: {
            Text(JournalReadout.answer(value))
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(isChosen ? SharpitColor.primaryForeground : SharpitColor.slate)
                .frame(minWidth: 52, minHeight: 38)
                .background(isChosen ? SharpitColor.primary : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.sharpitPressable)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityHint(isChosen ? String(localized: "Touche de nouveau pour retirer ta réponse") : "")
    }
}

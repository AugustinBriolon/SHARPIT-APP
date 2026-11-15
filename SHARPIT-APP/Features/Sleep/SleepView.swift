import Charts
import SwiftUI

/// The night behind the day's sleep score: the score, time in bed and asleep, the sleep
/// coach and tonight's bedtime, the structure of the night, the sleep bank, then the
/// last fourteen nights.
struct SleepView: View {
    @State private var store: DayResourceStore<V1SleepResponse>
    @State private var showsTargets = false
    /// The night's course from Apple Health, with the day it belongs to: a night is never
    /// drawn with another one's course.
    @State private var course: (dayId: String, segments: [HealthSleepSample]) = ("", [])
    private let day: Date
    private let tokenProvider: () async throws -> String
    private let profileClient: any AthleteProfileServing
    private let syncClient: any SyncServing

    init(
        client: any SleepServing,
        tokenProvider: @escaping () async throws -> String,
        day: Date = .now,
        dataDaysClient: any DataDaysServing = SharpitClient(),
        syncClient: any SyncServing = SharpitClient(),
        profileClient: any AthleteProfileServing = AthleteProfileClient()
    ) {
        self.day = day
        self.syncClient = syncClient
        self.tokenProvider = tokenProvider
        self.profileClient = profileClient
        _store = State(initialValue: DayResourceStore(
            failureMessage: String(localized: "Ton sommeil n'a pas pu être chargé."),
            tokenProvider: tokenProvider,
            day: day,
            dataDays: { try await dataDaysClient.dataDays(domain: .sleep, from: $0, to: $1, token: $2) },
            fetch: { try await client.sleep(trainingDayId: $0, token: $1) }
        ))
    }

    /// Pulls the providers — the night may simply not have arrived yet — then reads every day again.
    private func syncAndReload() async {
        if let token = try? await tokenProvider() {
            _ = try? await syncClient.sync(token: token)
        }
        await store.reloadAll()
    }

    var body: some View {
        DayDetailScaffold(
            title: String(localized: "Sommeil"),
            emptySymbol: "moon.zzz",
            unavailableTitle: String(localized: "Sommeil indisponible"),
            store: store,
            content: { sleep in SleepSections(sleep: sleep, segments: sleep.trainingDayId == course.dayId ? course.segments : []) },
            emptyAction: (title: String(localized: "Synchroniser maintenant"), run: syncAndReload),
            wash: .sleep,
            dayLabel: SleepSheetReadout.nightLabel
        )
        // The sleep targets, set where they are read — right of the title, beside « Aujourd'hui ».
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // One action: the button itself, not a menu holding it.
                Button { showsTargets = true } label: {
                    Label("Objectifs de sommeil", systemImage: "target")
                }
            }
        }
        // Read for the day on screen, not only the one the page opened on.
        .task(id: store.selectedDay) {
            let selected = store.selectedDay
            let reader = HealthKitReader()
            guard reader.isAvailable else { return }
            let segments = await reader.sleepSegments(nightEndingOn: selected)
            course = (TrainingDayId.today(now: selected), segments)
        }
        .sheet(isPresented: $showsTargets, onDismiss: { Task { await store.load() } }) {
            SleepTargetsSheet(profileClient: profileClient, tokenProvider: tokenProvider)
        }
    }
}

/// The column itself, apart from its scroll view so it can be rendered on its own.
struct SleepSections: View {
    let sleep: V1SleepResponse
    var segments: [HealthSleepSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SleepHero(sleep: sleep, segments: segments)
            if sleep.history.contains(where: { $0.minutes != nil }) {
                SleepHistorySection(history: sleep.history, targetMin: sleep.targetMin, selected: sleep.trainingDayId)
                    .padding(.top, 18)
            }
            VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                SleepShapeSection(sleep: sleep)
                SleepCoachCard(sleep: sleep)
                SleepBankSection(sleep: sleep)
            }
            .padding(.top, SharpitSpacing.section)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, SharpitSpacing.xl)
    }
}

// MARK: - The night

/// The night as its mock-up reads it: a status pill, the time asleep, the score against the
/// need, the night's course by stage, then each stage on a line.
private struct SleepHero: View {
    let sleep: V1SleepResponse
    var segments: [HealthSleepSample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                CliniqueStatusPill(sleep.adequacy.label, status: SleepSheetReadout.status(sleep.adequacy.key))
                Text(SleepReadout.duration(sleep.durationMin))
                    .font(SharpitTypography.system(size: 44, weight: .semibold, relativeTo: .largeTitle, digits: true))
                    .tracking(-1.5)
                    .foregroundStyle(sleep.durationMin == nil ? SharpitColor.slate : SharpitColor.foreground)
                Text(SleepSheetReadout.scoreLine(sleep))
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)
            .accessibilityElement(children: .combine)

            if sleep.nightStatus == .present {
                night
                stages.padding(.top, 14)
            } else {
                Text(sleep.nightStatus == .pending
                     ? String(localized: "La nuit n'est pas encore synchronisée.")
                     : String(localized: "Aucune nuit enregistrée pour ce jour."))
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.slate)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The night from bedtime to waking: its course by stage when the watch recorded it, the
    /// stages' shares otherwise, under the clocks of its two ends.
    private var night: some View {
        VStack(spacing: 8) {
            if segments.isEmpty {
                HStack {
                    Text(SleepReadout.clock(sleep.bedtimeMin))
                    Spacer()
                    Text(SleepReadout.clock(sleep.wakeMin))
                }
                .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption, digits: true))
                .foregroundStyle(SharpitColor.slate)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Couché à \(SleepReadout.clock(sleep.bedtimeMin)), levé à \(SleepReadout.clock(sleep.wakeMin))")
                shareBar
            } else {
                SleepTimeline(segments: segments)
            }
        }
    }

    /// The night without its course (a watch that kept only the totals): the same four lanes as
    /// the timeline — awake on top, deep at the foot — each stage one block as long as its share
    /// of the night. It says how much of each, never when: every block starts at the left.
    @ViewBuilder
    private var shareBar: some View {
        let lanes = SleepSheetReadout.lanes(sleep.stages)
        if !lanes.isEmpty {
            GeometryReader { geo in
                ForEach(lanes, id: \.level) { lane in
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(lane.level.tone)
                        .frame(width: max(geo.size.width * lane.share, 6), height: 20)
                        .offset(y: SleepSheetReadout.laneOffset(lane.level))
                }
            }
            .frame(height: 96)
            .accessibilityHidden(true)
        }
    }

    /// Each stage on a line — its mark, its name beside its share of the sleep, its length —
    /// then the time awake.
    private var stages: some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            ForEach([SleepReadout.Stage.deep, .light, .rem]) { stage in
                stageRow(
                    tone: stage.tone, label: stage.label,
                    detail: SleepSheetReadout.share(stage.minutes(in: sleep.stages), of: sleep.stages),
                    value: SleepReadout.duration(stage.minutes(in: sleep.stages))
                )
                CliniqueDivider()
            }
            stageRow(
                tone: SleepReadout.TimelineLevel.awake.tone, label: String(localized: "Éveils"),
                detail: SleepSheetReadout.awakenings(segments), value: SleepReadout.duration(sleep.stages.awakeMin)
            )
            CliniqueDivider()
        }
    }

    private func stageRow(tone: Color, label: String, detail: String?, value: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tone)
                .frame(width: 5, height: 20)
                .accessibilityHidden(true)
            (Text(label).foregroundStyle(SharpitColor.foreground)
                + Text(detail.map { " \($0)" } ?? "").foregroundStyle(SharpitColor.slate))
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body, digits: true))
            Spacer(minLength: SharpitSpacing.xs)
            Text(value)
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// What shaped the score, as thin bars in the sleep hue, the night's efficiency last.
private struct SleepShapeSection: View {
    let sleep: V1SleepResponse

    var body: some View {
        let parts = SleepReadout.components(sleep.breakdown)
        let inBed = SleepReadout.timeInBed(bedtime: sleep.bedtimeMin, wake: sleep.wakeMin)
        if sleep.nightStatus == .present, !parts.isEmpty {
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                SleepSectionTitle(String(localized: "Ce qui l'a façonné"))
                ForEach(parts, id: \.label) { part in
                    row(part.label, "\(Int(part.value.rounded()))", fraction: part.value / 100)
                }
                if let asleep = sleep.durationMin, let inBed, inBed > 0 {
                    row(String(localized: "Efficacité"), SleepReadout.efficiency(asleep: asleep, inBed: inBed), fraction: asleep / inBed)
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, fraction: Double) -> some View {
        HStack(spacing: SharpitSpacing.md) {
            Text(label)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.foreground)
                .frame(width: 120, alignment: .leading)
            SharpitBarTrack(fraction: fraction, tone: SharpitColor.pillarSleep)
                .frame(height: 4)
            Text(value)
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
                .fixedSize()
                .frame(minWidth: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A section's name on the sheet.
private struct SleepSectionTitle: View {
    let title: String
    var trailing: String? = nil
    var pill: (label: String, status: CliniqueStatus)? = nil

    init(_ title: String, trailing: String? = nil, pill: (String, CliniqueStatus)? = nil) {
        self.title = title
        self.trailing = trailing
        self.pill = pill.map { (label: $0.0, status: $0.1) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(SharpitTypography.sectionTitle)
                .tracking(SharpitTypography.sectionTitleTracking)
                .foregroundStyle(SharpitColor.foreground)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: SharpitSpacing.xs)
            if let trailing {
                Text(trailing)
                    .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                    .foregroundStyle(SharpitColor.slate)
            }
            if let pill {
                CliniqueStatusPill(pill.label, status: pill.status)
            }
        }
    }
}

/// How the night reads at the head of its sheet.
enum SleepSheetReadout {
    /// Where a stage's lane sits, awake on top and deep sleep at the foot.
    static func laneOffset(_ level: SleepReadout.TimelineLevel) -> CGFloat {
        switch level {
        case .awake: 0
        case .rem: 25
        case .light: 50
        case .deep: 76
        }
    }

    /// Each stage's share of the time in bed, longest lane full width; empty when no stage was kept.
    static func lanes(_ stages: V1SleepStages) -> [(level: SleepReadout.TimelineLevel, share: Double)] {
        let minutes: [(SleepReadout.TimelineLevel, Double)] = [
            (.awake, stages.awakeMin ?? 0), (.rem, stages.remMin ?? 0),
            (.light, stages.lightMin ?? 0), (.deep, stages.deepMin ?? 0),
        ]
        guard let longest = minutes.map(\.1).max(), longest > 0 else { return [] }
        return minutes.filter { $0.1 > 0 }.map { (level: $0.0, share: $0.1 / longest) }
    }

    static func status(_ key: V1SleepAdequacy.Key) -> CliniqueStatus {
        switch key {
        case .excellent, .adequate: .good
        case .insufficient: .watch
        case .severelyInsufficient: .alert
        case .pending, .missing, .unknown: .unknown
        }
    }

    /// « Score 64 / 100 · 1 h 10 de moins que ton besoin »: the score, then the night against
    /// its target when they differ.
    static func scoreLine(_ sleep: V1SleepResponse) -> String {
        var parts: [String] = []
        if let score = sleep.score { parts.append(String(localized: "Score \(Int(score.rounded())) / 100")) }
        if let need = need(sleep.targetDeltaMin) { parts.append(need) }
        return parts.isEmpty ? String(localized: "Pas encore de score") : parts.joined(separator: " · ")
    }

    static func need(_ deltaMin: Double?) -> String? {
        guard let deltaMin, abs(deltaMin) >= 1 else { return nil }
        let length = SleepReadout.duration(abs(deltaMin))
        return deltaMin < 0
            ? String(localized: "\(length) de moins que ton besoin")
            : String(localized: "\(length) de plus que ton besoin")
    }

    /// A stage's share of the sleep, « 19 % »; nil when it was not recorded.
    static func share(_ minutes: Double?, of stages: V1SleepStages) -> String? {
        let total = [stages.deepMin, stages.remMin, stages.lightMin].compactMap { $0 }.reduce(0, +)
        guard let minutes, total > 0 else { return nil }
        return "\(Int((minutes / total * 100).rounded())) %"
    }

    /// « Nuit du 13 nov. »: a day's sleep is the night that ended on it.
    static func nightLabel(_ day: Date) -> String {
        let evening = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        return String(localized: "Nuit du \(evening.sharpitFormatted(.dateTime.day().month(.abbreviated)))")
    }

    /// « 7 h 08 », the mean of the nights read; nil without one.
    static func average(_ minutes: [Double]) -> String? {
        minutes.isEmpty ? nil : SleepReadout.duration(minutes.reduce(0, +) / Double(minutes.count))
    }

    /// « 3 fois »: the stretches awake the watch recorded; nil without the night's course.
    static func awakenings(_ segments: [HealthSleepSample]) -> String? {
        let count = segments.filter { $0.stage == .awake }.count
        guard count > 0 else { return nil }
        return String(localized: "\(count) fois")
    }

    /// The clocks over the night's course: its two ends, and the even hours far enough from
    /// both to be read. Each with its place along the night, 0 to 1.
    static func axis(start: Date, end: Date, calendar: Calendar = .current) -> [(label: String, at: Double)] {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return [] }
        func clock(_ date: Date) -> String {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return "\(parts.hour ?? 0) h \(String(format: "%02d", parts.minute ?? 0))"
        }
        var marks: [(label: String, at: Double)] = [(clock(start), 0)]
        var hour = calendar.nextDate(after: start, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? end
        while hour < end {
            let at = hour.timeIntervalSince(start) / span
            if calendar.component(.hour, from: hour) % 2 == 0, at > 0.18, at < 0.82 {
                marks.append(("\(calendar.component(.hour, from: hour)) h", at))
            }
            hour = hour.addingTimeInterval(3_600)
        }
        marks.append((clock(end), 1))
        return marks
    }
}

/// Tonight, as lines: when to go to bed, when to put the screens down, what the night owes —
/// then what the coach reads in the recent nights, and the way to talk about it.
private struct SleepCoachCard: View {
    @Environment(ShellRouter.self) private var router
    let sleep: V1SleepResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SleepSectionTitle(String(localized: "Ce soir"))
                .padding(.bottom, 4)
            if let bedtime = sleep.recommendedBedtimeMin {
                SleepLine(String(localized: "Au lit vers"), value: SleepReadout.clock(bedtime))
                CliniqueDivider()
                if let windDown = sleep.windDownStartMin {
                    SleepLine(String(localized: "Écrans coupés vers"), value: SleepReadout.clock(windDown))
                    CliniqueDivider()
                }
                // ADR-079: the need grows with the debt, the day's effort and a poor efficiency.
                if let duration = sleep.sleepNeededMin ?? sleep.recommendedDurationMin {
                    SleepLine(String(localized: "Besoin cette nuit"), detail: needDetail, value: SleepReadout.duration(duration))
                    CliniqueDivider()
                }
            }
            ForEach(sleep.insights, id: \.self) { insight in
                VStack(alignment: .leading, spacing: 3) {
                    Text(insight.title)
                        .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(SharpitColor.foreground)
                    Text(insight.detail)
                        .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                        .lineSpacing(2)
                        .foregroundStyle(SharpitColor.slate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 14)
                .accessibilityElement(children: .combine)
                CliniqueDivider()
            }
            HStack(spacing: 12) {
                Text(sleep.recoveryNote ?? String(localized: "Une question sur tes nuits ?"))
                    .font(SharpitTypography.system(size: 14, weight: .regular, relativeTo: .footnote))
                    .lineSpacing(2)
                    .foregroundStyle(SharpitColor.slate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    router.discussWithCoach(about: CoachDiscuss.describe(.today))
                } label: {
                    Text("En parler au coach")
                        .font(SharpitTypography.system(size: 14, weight: .semibold, relativeTo: .footnote))
                        .foregroundStyle(SharpitColor.foreground)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.sharpitPressable)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(SharpitColor.divider, lineWidth: 1))
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var needDetail: String? {
        guard let contributors = sleep.sleepNeededContributors else { return nil }
        let bits = [
            contributors.debtBoostMin > 0 ? String(localized: "dette +\(Int(contributors.debtBoostMin)) min") : nil,
            contributors.strainBoostMin > 0 ? String(localized: "effort +\(Int(contributors.strainBoostMin)) min") : nil,
            contributors.efficiencyBoostMin > 0 ? String(localized: "efficacité +\(Int(contributors.efficiencyBoostMin)) min") : nil,
        ].compactMap { $0 }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }
}

/// A name, what it rests on, its figure: one line of the sheet.
private struct SleepLine: View {
    let name: String
    var detail: String? = nil
    let value: String

    init(_ name: String, detail: String? = nil, value: String) {
        self.name = name
        self.detail = detail
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .body))
                    .foregroundStyle(SharpitColor.foreground)
                if let detail {
                    Text(detail)
                        .font(SharpitTypography.system(size: 13, weight: .regular, relativeTo: .caption, digits: true))
                        .foregroundStyle(SharpitColor.slate)
                }
            }
            Spacer(minLength: SharpitSpacing.sm)
            Text(value)
                .font(SharpitTypography.system(size: 15, weight: .semibold, relativeTo: .body, digits: true))
                .foregroundStyle(SharpitColor.foreground)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Last night

/// The night's course: one rounded block per stretch of a stage, awake on top and deep sleep at
/// the foot, under the clocks of the night.
private struct SleepTimeline: View {
    let segments: [HealthSleepSample]


    var body: some View {
        let blocks = segments.compactMap { segment in
            SleepReadout.TimelineLevel(segment.stage).map { (level: $0, start: segment.start, end: segment.end) }
        }
        if let start = blocks.map(\.start).min(), let end = blocks.map(\.end).max(), end > start {
            let span = end.timeIntervalSince(start)
            VStack(spacing: 8) {
                GeometryReader { geo in
                    ForEach(Array(SleepSheetReadout.axis(start: start, end: end).enumerated()), id: \.offset) { _, mark in
                        Text(mark.label)
                            .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption, digits: true))
                            .foregroundStyle(SharpitColor.slate)
                            .fixedSize()
                            .alignmentGuide(.leading) { $0.width * mark.at }
                            .offset(x: geo.size.width * mark.at)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(height: 16)
                GeometryReader { geo in
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(block.level.tone)
                            .frame(width: max(geo.size.width * block.end.timeIntervalSince(block.start) / span, 4), height: 20)
                            .offset(x: geo.size.width * block.start.timeIntervalSince(start) / span, y: SleepSheetReadout.laneOffset(block.level))
                    }
                }
                .frame(height: 96)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Déroulé de la nuit par phase")
        }
    }
}

// MARK: - Sleep bank

/// What the recent nights owe the athlete, and how steady they were — a line each.
private struct SleepBankSection: View {
    let sleep: V1SleepResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SleepSectionTitle(
                String(localized: "Banque de sommeil"),
                pill: sleep.debt7Min.map { $0.rounded() <= 0
                    ? (String(localized: "À l'équilibre"), CliniqueStatus.good)
                    : (String(localized: "En dette"), CliniqueStatus.watch) }
            )
            .padding(.bottom, 4)
            SleepLine(String(localized: "Solde 7 jours"), value: SleepReadout.bankBalance(debtMin: sleep.debt7Min))
            CliniqueDivider()
            SleepLine(String(localized: "Solde 14 jours"), value: SleepReadout.bankBalance(debtMin: sleep.debt14Min))
            CliniqueDivider()
            SleepLine(String(localized: "Moyenne 7 jours"), value: SleepReadout.duration(sleep.averages.durationMin))
            CliniqueDivider()
            SleepLine(
                String(localized: "Régularité"),
                value: sleep.regularityMin.map { String(localized: "± \(Int($0.rounded())) min") } ?? "—"
            )
            CliniqueDivider()
            SleepLine(String(localized: "Score moyen"), value: sleep.averages.score.map { "\(Int($0.rounded()))" } ?? "—")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Trends

/// The last nights as bars against the need: the night read is the one in full colour, orange
/// when it fell short.
private struct SleepHistorySection: View {
    let history: [V1SleepNight]
    let targetMin: Double
    var selected: String? = nil

    var body: some View {
        let nights = history.suffix(14)
        let lengths = nights.compactMap(\.minutes)
        let top = max(lengths.max() ?? 0, targetMin, 1) * 1.08
        VStack(alignment: .leading, spacing: 12) {
            SleepSectionTitle(
                nights.count == 1 ? String(localized: "Dernière nuit") : String(localized: "\(nights.count) dernières nuits"),
                trailing: SleepSheetReadout.average(lengths).map { String(localized: "moyenne \($0)") }
            )
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(nights) { night in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(tone(night))
                        .frame(height: max(70 * (night.minutes ?? 0) / top, night.minutes == nil ? 0 : 4))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 70, alignment: .bottom)
            .background(alignment: .top) {
                Rectangle()
                    .stroke(SharpitColor.outline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 1)
                    .clipped()
                    .offset(y: 70 * (1 - targetMin / top))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Durée de sommeil sur \(nights.count) nuits, besoin \(SleepReadout.duration(targetMin))")
        }
    }

    private func tone(_ night: V1SleepNight) -> Color {
        guard night.date == (selected ?? history.last?.date) else { return SharpitColor.pillarSleep.opacity(0.22) }
        return (night.minutes ?? 0) >= targetMin ? SharpitColor.pillarSleep : SharpitColor.statusWatchMark
    }
}

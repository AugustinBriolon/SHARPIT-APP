#if DEBUG
import SwiftUI

/// The Ink & Lime references (ADR-085), rebuilt from the shared components, to compare them
/// with the mock-ups in the simulator without an account. Debug builds only:
/// `-SharpitDesignGallery YES`, or `defaults write app.sharpit.ios SharpitDesignGallery -bool YES`
/// in the simulator when the launcher cannot pass arguments.
enum DesignGalleryDemo {
    static var isRequested: Bool {
        UserDefaults.standard.bool(forKey: "SharpitDesignGallery")
    }
}

struct DesignGalleryHost: View {
    @State private var range = "6M"

    var body: some View {
        ScrollView {
            VStack(spacing: SharpitSpacing.lg) {
                strengthCard
                cardioCard
                sleepCard
                restCard
                progressCard
                setsCard
                summaryCard
            }
            .padding(SharpitSpacing.pageInset)
        }
        .background(SharpitCanvasBackground())
    }

    private var strengthCard: some View {
        GalleryCard {
            SharpitCardHeader(title: String(localized: "Force"), symbol: "dumbbell.fill", subtitle: String(localized: "Développé couché · cette semaine"), showsChevron: false) {
                SharpitPill("NOUVEAU PR", style: .lime)
            }
            SharpitHeroFigure(value: "102,5", unit: "kg", delta: String(localized: "+5 kg"))
            Text("Ton précédent record était 97,5 kg")
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body))
                .foregroundStyle(SharpitColor.mutedForeground)
            SharpitProgressBar(label: String(localized: "Prochain palier"), value: "102,5 / 110 kg", fraction: 0.9)
        }
    }

    private var cardioCard: some View {
        GalleryCard {
            SharpitCardHeader(title: String(localized: "Cardio"), symbol: "bolt.fill", subtitle: String(localized: "5 km le plus rapide · cette semaine"), showsChevron: false)
            SharpitHeroFigure(value: "22:14", unit: "minutes")
            SharpitGoalTrack(
                fraction: SharpitProgressMath.fraction(start: 1382, current: 1334, goal: 1260),
                nowLabel: "now",
                nowValue: "22:14",
                startValue: "23:02",
                startLabel: String(localized: "Record précédent"),
                goalValue: "21:00",
                goalLabel: String(localized: "Prochain objectif")
            )
        }
    }

    private var sleepCard: some View {
        GalleryCard {
            SharpitCardHeader(title: String(localized: "Score de sommeil"), symbol: "moon.fill", subtitle: String(localized: "Cette nuit · 7 h 32"), showsChevron: false)
            ZStack {
                SharpitTickGauge(score: 86, showsScale: true)
                VStack(spacing: SharpitSpacing.xxs) {
                    Text("86")
                        .font(SharpitTypography.system(size: 64, weight: .heavy, relativeTo: .largeTitle, digits: true))
                        .tracking(-2)
                    Text("sur 100")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                    SharpitPill(String(localized: "↑ 8 vs moy."), style: .limeSoft)
                }
                .offset(y: 10)
            }
            .padding(.horizontal, SharpitSpacing.xl)
            Divider().overlay(SharpitColor.border)
            SharpitEyebrow(String(localized: "Ce qui l'a façonné"))
            VStack(spacing: SharpitSpacing.md) {
                breakdown(String(localized: "Durée"), 94)
                breakdown(String(localized: "Sommeil profond"), 91)
                breakdown(String(localized: "Récupération"), 88)
                breakdown(String(localized: "Régularité"), 72)
            }
        }
    }

    private func breakdown(_ label: String, _ value: Int) -> some View {
        HStack(spacing: SharpitSpacing.md) {
            Text(label)
                .font(SharpitTypography.system(size: 16, weight: .medium, relativeTo: .body))
                .frame(width: 130, alignment: .leading)
            SharpitBarTrack(fraction: Double(value) / 100, tone: SharpitColor.foreground)
                .frame(height: 8)
            Text("\(value)")
                .font(SharpitTypography.system(size: 17, weight: .bold, relativeTo: .body, digits: true))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var restCard: some View {
        GalleryCard {
            VStack(alignment: .leading, spacing: 2) {
                Text("Repos").font(SharpitTypography.cardTitle)
                Text("Développé couché · série 3 sur 4")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            ZStack {
                SharpitScoreRing(fraction: 0.8, lineWidth: 18)
                VStack(spacing: 4) {
                    Text("1:00")
                        .font(SharpitTypography.system(size: 56, weight: .heavy, relativeTo: .largeTitle, digits: true))
                    Text("avant la prochaine série")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .frame(width: 210, height: 210)
            .frame(maxWidth: .infinity)
            HStack(spacing: SharpitSpacing.sm) {
                SharpitPrimaryButton(title: "+15 s", style: .secondary) {}
                SharpitPrimaryButton(title: String(localized: "Pause"), style: .accent, trailingSymbol: "pause.circle.fill") {}
                SharpitPrimaryButton(title: String(localized: "Passer"), trailingSymbol: "forward.circle.fill") {}
            }
        }
    }

    private var progressCard: some View {
        GalleryCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Développé couché").font(SharpitTypography.cardTitle)
                    Text("Progression")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
                Spacer()
                SharpitSegmentedControl(
                    selection: $range,
                    options: ["6S", "3M", "6M", "1A"].map { .init(value: $0, label: $0) }
                )
                .frame(width: 190)
            }
            SharpitHeroFigure(value: "102,5", unit: "kg")
            Divider().overlay(SharpitColor.border)
            HStack {
                SharpitStatTile(caption: String(localized: "Meilleure série"), value: "102,5×6", isFlat: true)
                SharpitStatTile(caption: String(localized: "Volume"), value: "3 590", unit: "kg", isFlat: true)
                SharpitStatTile(caption: String(localized: "Séances"), value: "14", isFlat: true)
            }
        }
    }

    private var setsCard: some View {
        GalleryCard {
            SharpitCardHeader(title: String(localized: "Développé couché"), symbol: "dumbbell.fill", subtitle: String(localized: "Barre · Pectoraux"), showsChevron: false) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Volume")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.mutedForeground)
                    SharpitRowFigure(value: "3 590", unit: "kg")
                }
            }
            SharpitInsetGroup {
                ForEach(Array([(12, "95"), (10, "100"), (8, "102,5"), (6, "105")].enumerated()), id: \.offset) { index, set in
                    SharpitInsetRow(title: "") {
                        SharpitNumberChip(number: index + 1)
                    } trailing: {
                        HStack(spacing: SharpitSpacing.lg) {
                            SharpitRowFigure(value: "\(set.0)", unit: "×")
                            SharpitRowFigure(value: set.1, unit: "kg")
                            SharpitCheckBox(isOn: true)
                        }
                    }
                }
                SharpitDashedAddButton(title: String(localized: "Ajouter une série")) {}
            }
        }
    }

    private var summaryCard: some View {
        GalleryCard {
            VStack(alignment: .leading, spacing: 2) {
                Text("Push day").font(SharpitTypography.cardTitle)
                Text("Pectoraux · Épaules · Triceps")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.mutedForeground)
            }
            SharpitInsetGroup {
                SharpitInsetRow(title: String(localized: "Développé couché")) {
                    SharpitNumberChip(number: 1)
                } trailing: {
                    SharpitPill("PR", style: .lime)
                    SharpitRowFigure(value: "3 590", unit: "kg")
                }
                SharpitInsetRow(title: String(localized: "Écarté poulie")) {
                    SharpitNumberChip(number: 2)
                } trailing: {
                    SharpitRowFigure(value: "1 460", unit: "kg")
                }
            }
            SharpitProgressBar(label: String(localized: "Effort"), value: "RPE 8,5", fraction: 0.9)
            SharpitPrimaryButton(title: String(localized: "Enregistrer la séance")) {}
        }
    }
}

private struct GalleryCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.lg) { content }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
    }
}
#endif

#if DEBUG
import ClerkKit
import SwiftUI

/// A screen on demo data, to check its look in the simulator without an account.
/// Debug builds only: `defaults write app.sharpit.ios SharpitScreenDemo today|strength|sleep|records|session`.
enum ScreenDemo {
    static var requested: String? {
        UserDefaults.standard.string(forKey: "SharpitScreenDemo")
    }
}

struct ScreenDemoHost: View {
    let screen: String
    @State private var router = ShellRouter()
    @State private var toastCenter = SharpitToastCenter()

    var body: some View {
        Group {
            switch screen {
            case "sleep":
                if let sleep = Self.sleep {
                    NavigationStack {
                        ScrollView { SleepSections(sleep: sleep) }
                            .background(SharpitCanvasBackground())
                            .navigationTitle("Sommeil")
                    }
                }
            case "records":
                NavigationStack {
                    RecordsView(
                        store: RecordsStore(client: DemoRecords(), tokenProvider: { "demo" }),
                        activityClient: ActivityClient(),
                        tokenProvider: { "demo" }
                    )
                }
            case "today-extras":
                ScrollView {
                    VStack(spacing: SharpitSpacing.md) {
                        MorningProposalCard(
                            proposal: V1TodayMorningProposal(
                                checkInDone: false,
                                decisionId: "d", sessionId: "s", direction: .down,
                                changeSummary: String(localized: "Seuil raccourci à 30 min"),
                                why: String(localized: "Ta VFC est sous ta moyenne et la nuit a été courte."),
                                from: .init(intensityLabel: String(localized: "Seuil"), durationMin: 40, description: nil),
                                to: .init(intensityLabel: String(localized: "Endurance"), durationMin: 30, description: nil)
                            ),
                            onCheckIn: {},
                            onAnswer: { _ in }
                        )
                        ConsistencyStrip(
                            consistency: V1TodayConsistency(
                                days: (0..<7).map { index in
                                    V1TodayConsistencyDay(
                                        date: "2026-10-\(13 + index)",
                                        weekdayLabel: ["L", "M", "M", "J", "V", "S", "D"][index],
                                        dayOfMonth: 13 + index,
                                        hasActivity: [true, false, true, true, false, false, false][index],
                                        isToday: index == 3,
                                        isFuture: index > 3
                                    )
                                },
                                thisWeekSessionCount: 3
                            ),
                            consecutiveWeeks: 6
                        ) {}
                        TodayTimelineStrip(events: [
                            V1DayTimelineEvent(kind: "wake", minuteOfDay: 422, title: String(localized: "Réveil"), detail: String(localized: "7 h 32 de sommeil")),
                            V1DayTimelineEvent(kind: "checkin", minuteOfDay: 450, title: String(localized: "Check-in du matin"), detail: nil),
                            V1DayTimelineEvent(kind: "session", minuteOfDay: 1080, title: String(localized: "Seuil 40 min"), detail: String(localized: "Prévue")),
                        ])
                    }
                    .padding(SharpitSpacing.pageInset)
                }
                .background(SharpitCanvasBackground())
            case "strength":
                if let session = Self.strengthSession {
                    GuidedStrengthWorkoutView(
                        session: session,
                        finish: GuidedStrengthFinishContext(
                            client: ActivityClient(),
                            linker: PlannedSessionClient(),
                            tokenProvider: { "demo" }
                        )
                    )
                }
            case "stress":
                NavigationStack {
                    ScrollView { StressDemo.cards }
                        .background(SharpitCanvasBackground())
                        .navigationTitle("Valeurs extrêmes")
                }
            case "stress-sleep":
                if let sleep = StressDemo.sleep {
                    NavigationStack {
                        ScrollView { SleepSections(sleep: sleep) }
                            .background(SharpitCanvasBackground())
                            .navigationTitle("Sommeil")
                    }
                }
            case "stress-strength":
                if let session = StressDemo.strengthSession {
                    GuidedStrengthWorkoutView(
                        session: session,
                        finish: GuidedStrengthFinishContext(
                            client: ActivityClient(),
                            linker: PlannedSessionClient(),
                            tokenProvider: { "demo" }
                        )
                    )
                }
            case "form", "form-stress", "form-stress-bottom":
                ActivityFormSheet(
                    mode: .create,
                    draft: screen == "form" ? .new() : StressDemo.formDraft,
                    client: DemoActivityMutator(),
                    tokenProvider: { "demo" },
                    onSaved: { _ in }
                )
                .defaultScrollAnchor(screen.hasSuffix("bottom") ? .bottom : .top)
            case "session":
                // Full screen rather than in its sheet: the simulator cannot drag a detent open.
                PlannedSessionDrawer(
                    preview: .demo,
                    watch: SessionWatchContext(
                        session: V1PlannedSessionItem(id: "demo", date: PlannedSessionPreview.demoDate, type: "RUN"),
                        client: GarminWorkoutClient(),
                        tokenProvider: { "demo" },
                        onSent: {}
                    ),
                    onDiscussWithCoach: { _ in }
                )
            case "status":
                Color.clear.sheet(isPresented: .constant(true)) {
                    ActivityStatusButtonDemo()
                }
            default:
                TabView {
                    Tab("Résumé", systemImage: "sun.max") { TodayView() }
                }
            }
        }
        .environment(router)
        .environment(toastCenter)
        .environment(Clerk.shared)
    }

    private static var sleep: V1SleepResponse? {
        let nights = (1...14).map { day in
            #"{ "date": "2026-10-\#(String(format: "%02d", day))", "minutes": \#(400 + (day * 37) % 110) }"#
        }.joined(separator: ",")
        let json = #"""
        {
          "apiVersion": 1, "trainingDayId": "2026-10-14", "nightStatus": "present", "empty": null,
          "score": 86, "adequacy": { "key": "EXCELLENT", "label": "Ta meilleure nuit de la semaine." },
          "durationMin": 452, "targetMin": 480, "targetDeltaMin": -28, "delta7dMin": 32,
          "stages": { "deepMin": 92, "remMin": 110, "lightMin": 228, "awakeMin": 22 },
          "bedtimeMin": 1390, "wakeMin": 422,
          "breakdown": { "durationScore": 94, "architectureScore": 91, "restorativeRatio": 0.88 },
          "averages": { "score": 78, "durationMin": 434.4, "deepPct": 17.2, "remPct": 23, "nights": 7 },
          "regularityMin": 35.4, "recommendedBedtimeMin": 1350, "recommendedDurationMin": 495,
          "debt7Min": 96, "debt14Min": 150, "recoveryNote": null,
          "history": [\#(nights)],
          "insights": [{ "tone": "good", "title": "Sommeil profond", "detail": "32 minutes au-dessus de ton habitude." }],
          "confidencePct": 74
        }
        """#
        return try? JSONDecoder().decode(V1SleepResponse.self, from: Data(json.utf8))
    }

    private static var strengthSession: GuidedStrengthSession? {
        func exercise(_ name: String, sets: Int, reps: Int, kg: Double, order: Int) -> JSONValue {
            .object([
                "exercise": .string(name), "sets": .number(Double(sets)), "reps": .number(Double(reps)),
                "weightKg": .number(kg), "restSec": .number(90), "order": .number(Double(order)),
            ])
        }
        return GuidedStrengthSession.make(
            title: String(localized: "Push day"),
            plannedSessionId: nil,
            prescription: .object([
                "version": .number(1),
                "sets": .array([
                    exercise(String(localized: "Développé couché"), sets: 4, reps: 8, kg: 100, order: 0),
                    exercise(String(localized: "Développé militaire"), sets: 4, reps: 8, kg: 60, order: 1),
                    exercise(String(localized: "Écarté poulie"), sets: 3, reps: 12, kg: 20, order: 2),
                ]),
            ])
        )
    }
}
/// The figures and words no screen was drawn for — a six-figure volume, a name that runs two
/// lines, a night of 23 h, a streak of 999 weeks — to check in the simulator (iPhone mini, the
/// largest Dynamic Type, dark) that nothing clips, overlaps or traps.
/// `defaults write app.sharpit.ios SharpitScreenDemo stress|stress-sleep|stress-strength`.
private enum StressDemo {
    static let longName = String(localized: "Développé couché prise serrée sur banc incliné à 30° avec chaînes et élastiques")

    static var formDraft: ActivityDraft {
        var draft = ActivityDraft(date: .now.addingTimeInterval(-86_400))
        draft.sport = .run
        draft.title = longName
        draft.durationMin = 1435
        draft.distanceText = "999,99"
        draft.elevationText = "88888"
        draft.avgHrText = "219"
        draft.rpe = 10
        draft.feeling = .veryBad
        draft.notes = String(repeating: "Jambes lourdes, vent de face. ", count: 12)
        return draft
    }

    @MainActor static var cards: some View {
        VStack(spacing: SharpitSpacing.md) {
            ActivityStrengthSection(exercises: StrengthExerciseReadout.exercises(from: [
                V1ActivityStrengthSet(exercise: longName, sets: 12, reps: 30, durationSec: nil, weightKg: 287.5),
                V1ActivityStrengthSet(exercise: String(localized: "Squat"), sets: 10, reps: 10, durationSec: nil, weightKg: 1_250),
                V1ActivityStrengthSet(exercise: String(localized: "Gainage"), sets: 99, reps: 0, durationSec: 5_400, weightKg: nil),
                V1ActivityStrengthSet(exercise: String(localized: "Tractions"), sets: 3, reps: 12, durationSec: nil, weightKg: nil),
            ]))
            MorningProposalCard(
                proposal: V1TodayMorningProposal(
                    checkInDone: false,
                    decisionId: "d", sessionId: "s", direction: .down,
                    changeSummary: String(localized: "Seuil raccourci de 2 h 30 à 45 min et passé en endurance fondamentale stricte"),
                    why: String(repeating: String(localized: "Ta VFC est très sous ta moyenne, la nuit a été courte et ta charge aiguë dépasse ta charge chronique. "), count: 4),
                    from: .init(intensityLabel: String(localized: "Seuil anaérobie lactique"), durationMin: 1_439, description: nil),
                    to: .init(intensityLabel: String(localized: "Endurance fondamentale"), durationMin: 0, description: nil)
                ),
                onCheckIn: {},
                onAnswer: { _ in }
            )
            ConsistencyStrip(
                consistency: V1TodayConsistency(
                    days: (0..<7).map { index in
                        V1TodayConsistencyDay(
                            date: "2026-10-\(13 + index)",
                            weekdayLabel: ["L", "M", "M", "J", "V", "S", "D"][index],
                            dayOfMonth: 13 + index,
                            hasActivity: true,
                            isToday: index == 6,
                            isFuture: false
                        )
                    },
                    thisWeekSessionCount: 99
                ),
                consecutiveWeeks: 999
            ) {}
            TodayTimelineStrip(events: [
                V1DayTimelineEvent(kind: "wake", minuteOfDay: 0, title: String(localized: "Réveil"), detail: String(localized: "23 h 59 de sommeil")),
                V1DayTimelineEvent(kind: "session", minuteOfDay: 1, title: longName, detail: longName),
                V1DayTimelineEvent(kind: "session", minuteOfDay: 1_439, title: String(localized: "Fin de journée"), detail: nil),
            ])
        }
        .padding(SharpitSpacing.pageInset)
    }

    static var sleep: V1SleepResponse? {
        let nights = (1...14).map { day in
            #"{ "date": "2026-10-\#(String(format: "%02d", day))", "minutes": \#(day.isMultiple(of: 2) ? 0 : 1_439) }"#
        }.joined(separator: ",")
        let json = #"""
        {
          "apiVersion": 1, "trainingDayId": "2026-10-14", "nightStatus": "present", "empty": null,
          "score": 100, "adequacy": { "key": "EXCELLENT", "label": "\#(longName)" },
          "durationMin": 1439, "targetMin": 480, "targetDeltaMin": 959, "delta7dMin": -1200,
          "stages": { "deepMin": 600, "remMin": 500, "lightMin": 300, "awakeMin": 39 },
          "bedtimeMin": 0, "wakeMin": 1439,
          "breakdown": { "durationScore": 100, "architectureScore": 0, "restorativeRatio": 1 },
          "averages": { "score": 3, "durationMin": 1439, "deepPct": 99.9, "remPct": 0, "nights": 999 },
          "regularityMin": 720, "recommendedBedtimeMin": 1439, "recommendedDurationMin": 1439,
          "debt7Min": 9999, "debt14Min": 99999, "recoveryNote": "\#(longName)",
          "history": [\#(nights)],
          "insights": [{ "tone": "good", "title": "\#(longName)", "detail": "\#(longName) \#(longName)" }],
          "confidencePct": 100
        }
        """#
        return try? JSONDecoder().decode(V1SleepResponse.self, from: Data(json.utf8))
    }

    static var strengthSession: GuidedStrengthSession? {
        func exercise(_ name: String, sets: Int, reps: Int, kg: Double, order: Int) -> JSONValue {
            .object([
                "exercise": .string(name), "sets": .number(Double(sets)), "reps": .number(Double(reps)),
                "weightKg": .number(kg), "restSec": .number(600), "order": .number(Double(order)),
            ])
        }
        return GuidedStrengthSession.make(
            title: longName,
            plannedSessionId: nil,
            prescription: .object([
                "version": .number(1),
                "sets": .array([
                    exercise(longName, sets: 12, reps: 100, kg: 287.5, order: 0),
                    exercise(String(localized: "Squat"), sets: 10, reps: 50, kg: 1_250, order: 1),
                    exercise(String(localized: "Curl"), sets: 1, reps: 1, kg: 0.5, order: 2),
                ]),
            ])
        )
    }
}

/// Records as the server would send them, dated around now so « Nouveau record » shows.
private struct DemoRecords: RecordsServing {
    func records(token: String) async throws -> V1Records {
        let recent = ISO8601DateFormatter().string(from: .now.addingTimeInterval(-3 * 86_400))
        let json = #"""
        {
          "prs": {
            "run": [
              { "key": "run-distance", "label": "Plus longue sortie", "entries": [
                { "rank": 1, "value": 21400, "displayValue": "21,4 km", "sublabel": "5:02/km",
                  "activityId": "a1", "date": "\#(recent)", "title": "Semi" },
                { "rank": 2, "value": 18000, "displayValue": "18,0 km", "sublabel": "5:20/km",
                  "activityId": "a2", "date": "2026-08-01T07:00:00.000Z", "title": "Sortie longue" },
                { "rank": 3, "value": 16000, "displayValue": "16,0 km", "sublabel": "5:31/km",
                  "activityId": "a4", "date": "2026-06-11T07:00:00.000Z", "title": "Sortie" }
              ] }
            ],
            "bike": [], "swim": []
          },
          "powerCurve": [],
          "runBests": [
            { "meters": 5000, "label": "5 km", "entries": [
              { "rank": 1, "value": 1334, "displayValue": "22:14", "sublabel": "4:27/km",
                "activityId": "a3", "date": "\#(recent)", "title": "Parkrun" } ] },
            { "meters": 10000, "label": "10 km", "entries": [
              { "rank": 1, "value": 2860, "displayValue": "47:40", "sublabel": "4:46/km",
                "activityId": "a5", "date": "2026-05-01T07:00:00.000Z", "title": "10 km" } ] }
          ],
          "runEfforts": [], "bikeEfforts": [],
          "streamsAnalyzed": 180, "totalActivities": 214
        }
        """#
        return try JSONDecoder().decode(V1Records.self, from: Data(json.utf8))
    }
}
private struct DemoActivityMutator: ActivityMutating {
    func createActivity(_ fields: [String: JSONValue], token: String) async throws -> String { "demo" }
    func updateActivity(id: String, fields: [String: JSONValue], token: String) async throws {}
    func deleteActivity(id: String, token: String) async throws {}
}

private struct DemoActivityStatus: ActivityStatusServing {
    func activityStatus(token: String) async throws -> V1ActivityStatusStore {
        V1ActivityStatusStore(status: .injured, retention: .untilDate("2026-12-31"))
    }
    func setActivityStatus(_ write: V1ActivityStatusWrite, token: String) async throws -> V1ActivityStatusStore {
        V1ActivityStatusStore(status: write.status, retention: write.retention ?? .untilModified)
    }
}

/// The status drawer opened at once on a mode with an end date.
private struct ActivityStatusButtonDemo: View {
    @State private var store = ActivityStatusStore(client: DemoActivityStatus(), tokenProvider: { "demo" })

    var body: some View {
        ActivityStatusDrawer(store: store)
            .task { await store.load() }
    }
}

/// A threshold run with its routines, one of them the coach's: the drawer's demo
/// (`SharpitScreenDemo session`) and its snapshot.
extension PlannedSessionPreview {
    /// Monday 26 October 2026, noon: a fixed day so the snapshot does not move with the clock.
    static let demoDate = Date(timeIntervalSince1970: 1_793_008_800)

    static var demo: PlannedSessionPreview {
        func move(_ name: String, _ dose: String, _ cue: String? = nil) -> V1RoutineMove {
            V1RoutineMove(name: name, dose: dose, cue: cue)
        }
        return PlannedSessionPreview(
            sessionId: "demo",
            title: String(localized: "Seuil 5 × 3 min"),
            sport: String(localized: "Course"),
            symbolName: "figure.run",
            date: demoDate,
            metrics: [
                PlannedSessionMetric(label: String(localized: "Durée"), value: "50 min"),
                PlannedSessionMetric(label: String(localized: "Intensité"), value: String(localized: "Seuil")),
                PlannedSessionMetric(label: String(localized: "Charge"), value: "62"),
            ],
            durationMin: 50,
            notes: nil,
            rationale: String(localized: "Ta VFC est revenue dans ta moyenne : on remet un peu d'intensité avant le week-end long."),
            steps: [
                V1PlannedSessionStep(key: "0-0", label: String(localized: "Échauffement"), detail: String(localized: "15 min"), group: "0"),
                V1PlannedSessionStep(key: "1-0", label: String(localized: "Bloc"), detail: String(localized: "3 min"), target: "4:05 – 4:20 /km", group: "1", repeatCount: 5),
                V1PlannedSessionStep(key: "1-1", label: String(localized: "Récup"), detail: "90 s", group: "1", repeatCount: 5),
                V1PlannedSessionStep(key: "2-0", label: String(localized: "Retour au calme"), detail: String(localized: "10 min"), group: "2"),
            ],
            stepsAreDerived: false,
            routines: V1SessionRoutines(
                warmup: V1SessionRoutine(moves: [
                    move("Rotations de chevilles", "10 par côté"),
                    move("Balancés de jambe avant-arrière", "10 par côté"),
                    move("Fentes marchées avec rotation du buste", "6 par côté"),
                    move("Montées de genoux", "2 × 20 m"),
                ], minutes: 4, source: "library"),
                cooldown: V1SessionRoutine(moves: [
                    move("Étirement du mollet contre un mur", "30 s par côté"),
                    move("Étirement des ischios, talon sur un support bas", "30 s par côté", "Dos droit, bascule du bassin"),
                    move("Fente basse, étirement du psoas", "30 s par côté", "Bassin rétroversé, sans cambrer"),
                ], minutes: 3, source: "coach")
            ),
            isKey: true
        )
    }
}
#endif

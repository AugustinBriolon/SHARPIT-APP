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
                .foregroundStyle(SharpitColor.slate)
            SharpitProgressBar(label: String(localized: "Prochain palier"), value: "102,5 / 110 kg", fraction: 0.9)
        }
    }

    private var cardioCard: some View {
        GalleryCard {
            SharpitCardHeader(title: String(localized: "Cardio"), symbol: "bolt.fill", subtitle: String(localized: "5 km le plus rapide · cette semaine"), showsChevron: false)
            SharpitHeroFigure(value: "22:14", unit: "minutes")
        }
    }

    private var sleepCard: some View {
        GalleryCard {
            SharpitCardHeader(title: String(localized: "Score de sommeil"), symbol: "moon.fill", subtitle: String(localized: "Cette nuit · 7 h 32"), showsChevron: false)
            ZStack {
                SharpitTickGauge(score: 86, showsScale: true, tone: SharpitColor.pillarSleep)
                VStack(spacing: SharpitSpacing.xxs) {
                    Text("86")
                        .font(SharpitTypography.system(size: 64, weight: .semibold, relativeTo: .largeTitle, digits: true))
                        .tracking(-2)
                    Text("sur 100")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.slate)
                    SharpitPill(String(localized: "↑ 8 vs moy."), style: .limeSoft)
                }
                .offset(y: 10)
            }
            .padding(.horizontal, SharpitSpacing.xl)
            Divider().overlay(SharpitColor.divider)
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
                .font(SharpitTypography.system(size: 16, weight: .regular, relativeTo: .body))
                .frame(width: 130, alignment: .leading)
            SharpitBarTrack(fraction: Double(value) / 100, tone: SharpitColor.foreground)
                .frame(height: 8)
            Text("\(value)")
                .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var restCard: some View {
        GalleryCard {
            VStack(alignment: .leading, spacing: 2) {
                Text("Repos").font(SharpitTypography.cardTitle)
                Text("Développé couché · série 3 sur 4")
                    .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(SharpitColor.slate)
            }
            ZStack {
                SharpitScoreRing(fraction: 0.8, lineWidth: 18)
                VStack(spacing: 4) {
                    Text("1:00")
                        .font(SharpitTypography.system(size: 56, weight: .semibold, relativeTo: .largeTitle, digits: true))
                    Text("avant la prochaine série")
                        .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                        .foregroundStyle(SharpitColor.slate)
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
                        .foregroundStyle(SharpitColor.slate)
                }
                Spacer()
                SharpitSegmentedControl(
                    selection: $range,
                    options: ["6S", "3M", "6M", "1A"].map { .init(value: $0, label: $0) }
                )
                .frame(width: 190)
            }
            SharpitHeroFigure(value: "102,5", unit: "kg")
            Divider().overlay(SharpitColor.divider)
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
                        .foregroundStyle(SharpitColor.slate)
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
                    .foregroundStyle(SharpitColor.slate)
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
/// Debug builds only: `defaults write app.sharpit.ios SharpitScreenDemo today|plan|activity|strength|sleep|sante|records|session`.
enum ScreenDemo {
    static var requested: String? {
        UserDefaults.standard.string(forKey: "SharpitScreenDemo")
    }
}

struct ScreenDemoHost: View {
    private static var recovery: V1RecoveryResponse? {
        let json = #"""
        {
          "apiVersion": 1, "trainingDayId": "2026-11-14", "empty": null,
          "readinessScore": 71, "signal": { "label": "Récupération correcte", "tone": "good" },
          "isCalibrating": false, "limiter": "Sommeil", "estimatedRecoveryDays": 1,
          "intensity": "Modérée",
          "rationale": ["Ton corps a encaissé hier, pas complètement. Le sommeil est ce qui te limite."],
          "dimensions": [
            { "key": "sleep", "score": 46, "status": "INSUFFICIENT" },
            { "key": "autonomic", "score": 55, "status": "NORMAL" },
            { "key": "subjective", "score": 74, "status": "NORMAL" },
            { "key": "loadContext", "score": 82, "status": "OPTIMAL" }
          ],
          "pillars": [
            { "key": "autonomic", "label": "Équilibre normal", "tone": "good" },
            { "key": "load", "label": "Charge optimale", "tone": "strong" }
          ],
          "dissonanceDetected": false,
          "today": { "hrv": 58, "restingHr": 49, "bodyBattery": 72, "hrvBaselineLow": 60, "hrvBaselineHigh": 68 },
          "history": [
            { "date": "2026-11-12", "hrv": 64, "restingHr": 47 },
            { "date": "2026-11-13", "hrv": 61, "restingHr": 48 },
            { "date": "2026-11-14", "hrv": 58, "restingHr": 49 }
          ],
          "alerts": [], "keyEvidence": ["Sommeil sous la cible deux nuits de suite"],
          "confidencePct": 92, "completenessLabel": "Complètes"
        }
        """#
        return try? JSONDecoder().decode(V1RecoveryResponse.self, from: Data(json.utf8))
    }

    /// A night's course, as the watch would record it.
    private static var night: [HealthSleepSample] {
        let start = Calendar.current.date(bySettingHour: 23, minute: 50, second: 0, of: .now.addingTimeInterval(-86_400)) ?? .now
        let course: [(HealthSleepSample.Stage, Double)] = [
            (.awake, 18), (.core, 55), (.deep, 44), (.core, 40), (.rem, 33), (.awake, 11),
            (.core, 51), (.deep, 25), (.rem, 44), (.core, 33), (.awake, 11),
        ]
        var at = start
        return course.map { stage, minutes in
            defer { at = at.addingTimeInterval(minutes * 60) }
            return HealthSleepSample(start: at, end: at.addingTimeInterval(minutes * 60), stage: stage)
        }
    }

    private static var health: V1HealthOverview {
        func marker(_ key: V1HealthMarker.Key, _ value: Double, _ label: String, _ tone: V1HealthTone, delta: Double? = nil) -> V1HealthMarker {
            V1HealthMarker(
                key: key, value: value, basis: .average7,
                norm: V1HealthNorm(band: "b", label: label, tone: tone, reference: ""),
                trend: delta.map { V1HealthTrend(recent: value, baseline: value - $0, delta: $0, stable: false, tone: tone) },
                series: (0..<30).map { day in
                    CorpsPoint(
                        date: Calendar.current.date(byAdding: .day, value: day - 29, to: .now) ?? .now,
                        value: value * (0.94 + 0.06 * Double(day) / 29) + sin(Double(day) / 2.5 + value) * value * 0.02
                    )
                }
            )
        }
        return V1HealthOverview(
            synthesis: V1HealthSynthesis(
                biologicalAge: V1BiologicalAge(years: 31, chronologicalYears: 34, method: nil, confidence: nil, computedAt: nil),
                normed: 7, inNorm: 6,
                highlights: [
                    V1HealthHighlight(key: .restingHr, delta: -3, tone: .good),
                    V1HealthHighlight(key: .sleep, delta: -28, tone: .watch),
                ]
            ),
            watch: [V1HealthWatch(key: "sleep", title: String(localized: "Nuits courtes"), detail: String(localized: "6 h 05 en moyenne sur 7 jours, sous ton besoin de 7 h 30."))],
            vitals: [
                marker(.restingHr, 47, String(localized: "Niveau athlète"), .good, delta: -3),
                marker(.hrv, 61, String(localized: "Dans ta plage habituelle"), .good),
                marker(.sleep, 365, String(localized: "Un peu court"), .watch, delta: -28),
                marker(.vo2max, 56, String(localized: "Bien au-dessus de ton âge"), .good),
            ],
            body: [
                marker(.weight, 71.4, String(localized: "Stable"), .neutral),
                marker(.bodyFatPct, 12.8, String(localized: "Athlétique"), .good, delta: -0.4),
            ]
        )
    }

    /// A building day inside its advised zone, the week's bars behind it.
    static let effort: V1EffortResponse? = try? JSONDecoder().decode(V1EffortResponse.self, from: Data(#"""
    { "apiVersion": 1, "trainingDayId": "2026-11-13", "empty": null,
      "strain": { "score": 14.2, "label": "Charge soutenue", "subtitle": "Une journée qui construit. Le dernier bloc de tempo t'a coûté plus que prévu.", "tone": "good" },
      "verdict": { "key": "MAINTAIN", "label": "Maintenir", "tone": "good" },
      "fatigueTypeLabel": null, "trainingCapacity": "FULL", "rationale": ["Charge aiguë proche de ta charge de fond."],
      "keyEvidence": [], "consecutiveDays": 2, "estimatedDaysToFresh": 1,
      "load": { "daily": 96, "weekly": 438, "acwr": 1.09, "chronicWeeklyAvg": 402, "tsb": -6, "avgWeeklyTss": 390 },
      "dimensions": [], "dominantDimension": null, "limitingFactor": null, "overreaching": null,
      "composition": { "available": false, "dominantKey": null, "contributors": [], "signals": { "steps": 9200, "stress": 28, "bodyBattery": 61 } },
      "pmc": [], "weeklyTss": [], "confidencePct": 82, "completenessLabel": "Complètes",
      "targetBand": { "algorithmVersion": "demo", "low": 11, "high": 15, "status": "within" },
      "strainPerformance": { "withinCount": 3, "dayCount": 4, "withinPct": 75, "history": [
        { "date": "2026-11-09", "strain": 6.1, "low": 5, "high": 9, "status": "within" },
        { "date": "2026-11-10", "strain": 13.4, "low": 11, "high": 15, "status": "within" },
        { "date": "2026-11-11", "strain": 0.8, "low": 0, "high": 4, "status": "within" },
        { "date": "2026-11-12", "strain": 10.5, "low": 5, "high": 9, "status": "above" },
        { "date": "2026-11-13", "strain": null, "low": 8, "high": 12, "status": null },
        { "date": "2026-11-14", "strain": null, "low": 12, "high": 16, "status": null },
        { "date": "2026-11-15", "strain": null, "low": 7, "high": 11, "status": null } ] } }
    """#.utf8))

    static let week: [V1GeneratedSession] = [
        V1GeneratedSession(date: "2026-11-16", type: .swim, intensity: "ENDURANCE", title: "Technique", description: "", durationMin: 60, load: 41),
        V1GeneratedSession(date: "2026-11-17", type: .run, intensity: "TEMPO", title: "Tempo 3 × 10 min", description: "", durationMin: 55, load: 68),
        V1GeneratedSession(date: "2026-11-19", type: .strength, intensity: "ENDURANCE", title: "Gainage", description: "", durationMin: 35, load: 0),
        V1GeneratedSession(date: "2026-11-20", type: .bike, intensity: "THRESHOLD", title: "Seuil 3 × 12 min", description: "", durationMin: 90, load: 85, isKey: true),
        V1GeneratedSession(date: "2026-11-22", type: .run, intensity: "ENDURANCE", title: "Sortie longue", description: "", durationMin: 100, load: 96),
    ]

    let screen: String
    @State private var router = ShellRouter()
    @State private var toastCenter = SharpitToastCenter()

    var body: some View {
        Group {
            switch screen {
            case "sleep":
                if let sleep = Self.sleep {
                    NavigationStack {
                        ScrollView { SleepSections(sleep: sleep, segments: Self.night).padding(.top, SharpitSpacing.md) }
                            .cliniqueSheet(wash: .sleep, height: 240)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) { Button {} label: { Image(systemName: "chevron.left") } }
                                ToolbarItem(placement: .topBarTrailing) { Button(SleepSheetReadout.nightLabel(.now)) {} .foregroundStyle(SharpitColor.foreground) }
                            }
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
            case "nutrition":
                NavigationStack {
                    ScrollView { NutritionSections(nutrition: NutritionReadout.placeholderResponse).padding(.top, SharpitSpacing.md) }
                        .cliniqueSheet(wash: .watch, height: 240)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) { Button {} label: { Image(systemName: "chevron.left") } }
                            ToolbarItem(placement: .topBarTrailing) { Button(DayDetailDatePicker.shortDay(.now)) {} .foregroundStyle(SharpitColor.foreground) }
                        }
                }
            case "recovery":
                if let recovery = Self.recovery {
                    NavigationStack {
                        ScrollView { RecoverySections(recovery: recovery).padding(.top, SharpitSpacing.md) }
                            .cliniqueSheet(wash: .good, height: 240)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) { Button {} label: { Image(systemName: "chevron.left") } }
                                ToolbarItem(placement: .topBarTrailing) { Button(DayDetailDatePicker.shortDay(.now)) {} .foregroundStyle(SharpitColor.foreground) }
                            }
                    }
                }
            case "sante":
                TabView {
                    Tab { NavigationStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                SanteHero(synthesis: Self.health.synthesis, vo2max: Self.health.marker(.vo2max))
                                    .padding(.top, SharpitSpacing.xs)
                                VStack(alignment: .leading, spacing: SharpitSpacing.section) {
                                    SanteTrends(markers: SanteTrendReadout.drawable(Self.health.allMarkers))
                                    SanteTable(title: SanteReadout.markers(Self.health.allMarkers.count), rows: Self.health.allMarkers.map(SanteTable.Row.init))
                                    SanteWatchSection(items: Self.health.watch)
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                            }
                        }
                        .cliniqueSheet(wash: .sleep, height: 240)
                        .toolbar {
                            SharpitBarTitle("Santé")
                            ToolbarItem(placement: .topBarTrailing) { Button {} label: { Image(systemName: "square.and.arrow.up") } }
                            SharpitBarGap()
                            ToolbarItem(placement: .topBarTrailing) { Button {} label: { Image(systemName: "plus") } }
                        }
                    } } label: { SharpitTabLabel("Santé", systemImage: "heart") }
                }
            case "journal":
                NavigationStack {
                    JournalView(client: DemoJournal(), wellness: WellnessClient(), tokenProvider: { "demo" })
                }
            case "pro":
                // Offers need the App Store: the simulator shows the page down to its plans' place.
                Color.clear.sheet(isPresented: .constant(true)) {
                    SharpitProPaywallSheet(store: ProStore(tokenProvider: { "demo" }))
                }
            case "loading":
                SharpitLoadingInstrument()
            case "teaser":
                ScrollView {
                    SharpitProTeaser(
                        title: String(localized: "Plan qui s’adapte"),
                        message: String(localized: "Le coach écrit ta semaine et la tient à jour avec SharpIt Pro. Tes séances déjà au plan restent à toi.")
                    )
                    .padding(24)
                }
                .cliniqueSheet(wash: .coach, height: 200)
            case "generator":
                // The proposal's lines on a fixed week: the sheet itself needs a finished job.
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        CliniqueStatusPill(String(localized: "Ta semaine est prête"), status: .good)
                        Text(GeneratedWeekReadout.title(Self.week) ?? "")
                            .font(SharpitTypography.system(size: 26, weight: .semibold, relativeTo: .title, digits: true))
                        Text(GeneratedWeekReadout.total(Self.week)).foregroundStyle(SharpitColor.slate)
                        GeneratedWeekView(sessions: Self.week, selection: [0, 1, 2, 3], onToggle: { _ in })
                    }
                    .padding(24)
                }
                .cliniqueSheet(wash: .good, height: 200)
            case "goals":
                NavigationStack {
                    GoalsView(store: GoalStore(client: DemoGoals(), plannedSessionClient: nil, profileClient: nil, activityClient: nil, tokenProvider: { "demo" }))
                }
            case "equipment":
                NavigationStack {
                    EquipmentView(client: DemoEquipment(), tokenProvider: { "demo" })
                }
            case "map":
                NavigationStack {
                    ActivityDetailView(activity: "demo-map", client: DemoActivities(), tokenProvider: { "demo" })
                }
            case "meal":
                NavigationStack { DemoMealPage() }
            case "portion":
                NavigationStack {
                    FoodPortionPage(product: DemoFoodLog.pasta, lastGrams: 200, meal: .dinner) { _, _ in }
                }
            case "compliance":
                if let analysis = try? JSONDecoder().decode(V1PlannedSessionAnalysis.self, from: Data("""
                {"complianceScore":72,"verdict":"too_hard","summary":"Les trois blocs sont faits, mais plus vite que prévu : tu es sorti de la zone tempo sur le dernier.",
                 "strengths":["Les trois blocs sont tenus","Durée respectée : 58 min pour 55 prévues"],
                 "improvements":["Allure 4:11 /km pour 4:20 – 4:30 prévus","Zone 4 au lieu de 3 sur le dernier bloc"],
                 "remarks":["Fréquence cardiaque moyenne 162 bpm"],
                 "recommendation":"Garde l'allure du premier bloc sur les trois : c'est là que le tempo travaille."}
                """.utf8)) {
                    ComplianceDetailSheet(title: "Tempo 3 × 10 min", analysis: analysis, onUnlink: {}, onReanalyze: {})
                }
            case "notifications":
                NavigationStack { NotificationPrefsView(profileClient: DemoEquipment(), tokenProvider: { "demo" }) }
            case "account":
                NavigationStack { AccountView(profileClient: DemoEquipment(), tokenProvider: { "demo" }, modelContext: nil) }
            case "targets":
                DemoTargetsSheet()
            case "ownfood":
                NavigationStack {
                    FoodCustomPage(purpose: .edit(DemoFoodLog.pasta), save: { _ in DemoFoodLog.pasta }, onSaved: { _ in })
                }
            case "recipe":
                NavigationStack {
                    FoodRecipePage(recipe: nil, client: DemoFoodLog(), tokenProvider: { "demo" }, onSave: { _ in DemoFoodLog.pasta }, onSaved: { _ in })
                }
            case "thresholds":
                NavigationStack {
                    ThresholdsView(client: AthleteProfileClient(), tokenProvider: { "demo" })
                }
            case "consent":
                PrivacyConsentWallView(reason: .documents, initial: nil, client: PrivacyConsentClient(), tokenProvider: { "demo" }) { _ in }
            case "connections":
                NavigationStack {
                    ConnectionsView(
                        appleHealth: AppleHealthSource(reader: HealthKitReader(), client: SharpitClient()),
                        appleCalendar: AppleCalendarSource(client: SharpitClient()),
                        syncClient: SharpitClient(),
                        tokenProvider: { "demo" }
                    )
                }
            case "ressenti":
                Color.clear.sheet(isPresented: .constant(true)) {
                    RessentiDuJourSheet(client: WellnessClient(), tokenProvider: { "demo" }, athleteId: "demo", onSaved: { _ in })
                }
            case "effort":
                if let effort = Self.effort {
                    NavigationStack {
                        ScrollView { EffortSections(effort: effort).padding(.top, SharpitSpacing.md) }
                            .cliniqueSheet(wash: .good, height: 240)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) { Button {} label: { Image(systemName: "chevron.left") } }
                                ToolbarItem(placement: .topBarTrailing) { Button(DayDetailDatePicker.shortDay(.now)) {} .foregroundStyle(SharpitColor.foreground) }
                            }
                    }
                }
            case "zones":
                NavigationStack {
                    SensitiveZonesView(store: SensitiveZonesStore(client: DemoZones(), tokenProvider: { "demo" }))
                }
            case "settings":
                // Live clients with a demo token: the rows show what they hold offline.
                SettingsView(
                    appleHealth: AppleHealthSource(reader: HealthKitReader(), client: SharpitClient()),
                    appleCalendar: AppleCalendarSource(client: SharpitClient()),
                    syncClient: SharpitClient(),
                    profileClient: AthleteProfileClient(),
                    displayMode: DisplayModeStore(client: AthleteProfileClient()),
                    features: FeatureStore(client: AthleteProfileClient()),
                    tokenProvider: { "demo" },
                    modelContext: nil
                )
            case "plan":
                TabView {
                    Tab("Plan", systemImage: "calendar") {
                        PlanView(
                            client: DemoPlan(), linker: PlannedSessionClient(),
                            activityClient: DemoActivities(), tokenProvider: { "demo" }
                        )
                    }
                }
            case "activity":
                TabView {
                    Tab("Activité", systemImage: "chart.line.uptrend.xyaxis") {
                        ActivityView(client: DemoActivities(), tokenProvider: { "demo" })
                    }
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
                        ResumeNutritionSection(phase: .loaded(NutritionReadout.placeholderDay)) {}
                        TodayTimelineStrip(events: [
                            V1DayTimelineEvent(kind: "wake", minuteOfDay: 422, title: String(localized: "Réveil"), detail: String(localized: "7 h 32 de sommeil")),
                            V1DayTimelineEvent(kind: "checkin", minuteOfDay: 450, title: String(localized: "Check-in du matin"), detail: nil),
                            V1DayTimelineEvent(kind: "session", minuteOfDay: 1080, title: String(localized: "Seuil 40 min"), detail: String(localized: "Prévue")),
                        ])
                    }
                    .padding(SharpitSpacing.pageInset)
                }
                .background(SharpitCanvasBackground())
            case "strength", "strength-dock":
                // The session run by the app: « Réduire » slides it away, the bar brings it back.
                GalleryWorkoutDockDemo(session: Self.strengthSession)
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
                            .cliniqueSheet(wash: .sleep)
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
            case "session-routines":
                // The summary alone, writable: the drawer only asks « Fait / Raccourci / Sauté »
                // with a plan editor, which the demo has none of.
                ScrollView {
                    PlannedSessionSummary(
                        preview: .demo,
                        steps: PlannedSessionPreview.demo.steps,
                        stepsAreDerived: false,
                        routines: PlannedSessionPreview.demo.routines,
                        onRoutineStatus: { _, _ in }
                    ) { EmptyView() }
                    .padding(SharpitSpacing.pageInset)
                }
                .background(SharpitCanvasBackground())
            case "status":
                Color.clear.sheet(isPresented: .constant(true)) {
                    ActivityStatusButtonDemo()
                }
            default:
                TabView {
                    Tab { TodayView() } label: { SharpitTabLabel("Résumé", systemImage: "house") }
                    Tab {
                        PlanView(
                            client: DemoPlan(), linker: PlannedSessionClient(),
                            activityClient: DemoActivities(), tokenProvider: { "demo" }
                        )
                    } label: { SharpitTabLabel("Plan", systemImage: "calendar") }
                    Tab { Color.clear } label: { SharpitTabLabel("Coach", systemImage: "bubble.left") }
                    Tab { Color.clear } label: { SharpitTabLabel("Activité", systemImage: "chart.line.uptrend.xyaxis") }
                    Tab { Color.clear } label: { SharpitTabLabel("Santé", systemImage: "heart") }
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
                    .object([
                        "exercise": .string(String(localized: "Étirement des fléchisseurs de la hanche")),
                        "sets": .number(3), "reps": .number(0), "durationSec": .number(30),
                        "perSide": .bool(true), "order": .number(3),
                    ]),
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

/// A week of prescriptions around today — two missed, today's key session, a brick ahead — to
/// check Plan's rows without an account, beside the sessions `DemoActivities` records.
private struct DemoPlan: PlannedSessionServing {
    func plannedSessions(from: Date, to: Date, token: String) async throws -> [V1PlannedSessionItem] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        return [
            V1PlannedSessionItem(id: "p1", date: day(-2), title: "Natation · Technique 2 400 m", type: "SWIM", durationMin: 55),
            V1PlannedSessionItem(id: "p2", date: day(-1), title: "Course · Tempo 3 × 10 min", type: "RUN", durationMin: 58, isKey: true),
            V1PlannedSessionItem(id: "p3", date: today, title: "Vélo · Seuil 2 × 12 min", type: "BIKE", durationMin: 75, isKey: true),
            V1PlannedSessionItem(id: "p4", date: day(1), title: "Vélo", type: "BIKE", durationMin: 100, brickGroupId: "b1", brickOrder: 0),
            V1PlannedSessionItem(id: "p5", date: day(1), title: "Course", type: "RUN", durationMin: 60, brickGroupId: "b1", brickOrder: 1),
            V1PlannedSessionItem(id: "p6", date: day(2), title: "Course · Sortie longue", type: "RUN", durationMin: 90),
        ].filter { $0.date >= from && $0.date <= to }
    }
}

/// Three weeks of done sessions around today, for Activité's list and Plan's done rows. A
/// session's detail is not served: the list is what the demo is for.
private struct DemoActivities: ActivityServing {
    func activities(token: String) async throws -> [V1ActivityListItem] {
        let formatter = ISO8601DateFormatter()
        func date(_ daysAgo: Int) -> String {
            formatter.string(from: Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(-daysAgo) * 86_400 + 7 * 3_600))
        }
        let rows: [(String, String, Int, String, Int, Int)] = [
            ("a1", "RUN", 1, "Tempo 3 × 10 min", 3_480, 72),
            ("a2", "BIKE", 3, "Endurance 1 h 45", 6_300, 88),
            ("a3", "SWIM", 4, "Technique 2 400 m", 3_300, 41),
            ("a4", "STRENGTH", 6, "Gainage", 1_500, 18),
            ("a5", "RUN", 8, "Sortie longue", 5_700, 96),
            ("a6", "BIKE", 10, "Seuil 3 × 12 min", 5_400, 85),
            ("a7", "RUN", 13, "Footing", 2_700, 38),
            ("a8", "SWIM", 15, "Endurance 2 000 m", 2_900, 36),
        ]
        let json = "[" + rows.map { id, type, daysAgo, title, duration, load in
            #"{"id":"\#(id)","type":"\#(type)","date":"\#(date(daysAgo))","title":"\#(title)","duration":\#(duration),"load":\#(load)}"#
        }.joined(separator: ",") + "]"
        return try JSONDecoder().decode([V1ActivityListItem].self, from: Data(json.utf8))
    }

    /// One run with its recording, for the map: every other session has no detail.
    func activity(id: String, token: String) async throws -> V1ActivityDetail {
        guard id == "demo-map" else { throw SharpitAPIError.server }
        return try JSONDecoder().decode(V1ActivityDetail.self, from: Data("""
        {"id":"demo-map","type":"RUN","date":"2026-11-12T07:30:00Z","title":"Tempo 3 × 10 min","duration":3480,
         "runMetrics":{"distanceM":12400,"elevationM":68}}
        """.utf8))
    }

    /// A loop around a lake, harder in its middle third.
    func activityStream(id: String, token: String) async throws -> V1ActivityStreamPayload {
        guard id == "demo-map" else { throw SharpitAPIError.server }
        let count = 160
        let path = (0..<count).map { index -> String in
            let angle = Double(index) / Double(count - 1) * 2 * Double.pi
            return "[\(45.9 + 0.012 * sin(angle)),\(6.13 + 0.02 * cos(angle) + 0.004 * sin(2 * angle))]"
        }
        let samples = (0..<count).map { index -> String in
            let effort = sin(Double(index) / Double(count - 1) * Double.pi)
            return "{\"t\":\(index * 22),\"d\":\(index * 78),\"hr\":\(128 + 43 * effort),\"speed\":\(3.2 + 0.8 * effort)}"
        }
        return try JSONDecoder().decode(V1ActivityStreamPayload.self, from: Data(
            "{\"available\":true,\"path\":[\(path.joined(separator: ","))],\"samples\":[\(samples.joined(separator: ","))]}".utf8
        ))
    }
    func generateNarrative(id: String, token: String) async throws -> V1ActivityDetail { throw SharpitAPIError.server }
    func updateSubjective(id: String, rpe: Double?, feeling: String?, token: String) async throws {}
}

/// A day half noted — a mood, two coffees, some water, one signal still open — and a reading.
private actor DemoJournal: JournalServing, JournalAnalysesServing {
    private var entry = V1DayJournalEntry(
        trainingDayId: "", factors: ["alcohol": .no], moodLabel: String(localized: "Correct"), hydrationMl: 1_200, caffeineMg: 160
    )
    private let prefs = JournalPrefs(raw: [
        "version": .number(2),
        "enabled": .object([
            "metric_mood": .bool(true), "metric_caffeine": .bool(true), "metric_hydration": .bool(true),
            "metric_driving": .bool(true), "alcohol": .bool(true), "nap": .bool(true),
        ]),
    ])

    func dayJournal(trainingDayId: String, token: String) async throws -> V1DayJournalEntry {
        entry.trainingDayId = trainingDayId
        return entry
    }

    func saveDayJournal(_ entry: V1DayJournalEntry, token: String) async throws -> V1DayJournalEntry {
        self.entry = entry
        return entry
    }

    func journalDaySignals(trainingDayId: String, token: String) async throws -> V1JournalDaySignals {
        V1JournalDaySignals(trainingDayId: trainingDayId)
    }

    func journalPrefs(token: String) async throws -> (prefs: JournalPrefs, isPro: Bool) { (prefs, true) }

    func saveJournalPrefs(_ prefs: JournalPrefs, token: String) async throws -> (prefs: JournalPrefs, isPro: Bool) { (prefs, true) }

    func journalAnalyses(token: String) async throws -> V1JournalAnalyses {
        V1JournalAnalyses(
            minDays: 7, daysWithSignal: 11, daysInSpan: 30,
            reading: V1JournalAnalysesReading(
                headline: String(localized: "Caféine après 15 h"),
                verdict: String(localized: "Score de sommeil 9 points plus bas, sur 11 nuits comparées."),
                summary: "", actionHint: "", strengths: []
            )
        )
    }
}

/// Two open zones — one with readings going down and a question owed — and a resolved one.
private struct DemoZones: SensitiveZoneServing {
    func sensitiveZonesData(token: String) async throws -> Data {
        Data(#"""
        { "apiVersion": 1, "bodyParts": ["Tendon d'Achille", "Bas du dos", "Genou"], "zones": [
          { "id": "z1", "title": "Tendon d'Achille gauche", "category": "INJURY", "categoryLabel": "Blessure",
            "bodyPart": "Tendon d'Achille", "side": "LEFT", "sideLabel": "Gauche", "status": "ACTIVE", "statusLabel": "Active",
            "severity": 2, "affectsTraining": true, "startDate": "2026-03-18T00:00:00.000Z",
            "strategy": "progressive", "strategyLabel": "En reprise",
            "strategyDetail": "Pas de côtes deux jours de suite, course plafonnée à 35 km par semaine.",
            "followUpQuestion": "Ton tendon d'Achille, ce matin ?",
            "timeline": [
              { "id": "r8", "date": "2026-11-13T00:00:00.000Z", "kind": "reading", "label": "2/10", "severity": 2 },
              { "id": "r7", "date": "2026-11-06T00:00:00.000Z", "kind": "reading", "label": "3/10", "severity": 3 },
              { "id": "r6", "date": "2026-10-30T00:00:00.000Z", "kind": "reading", "label": "4/10", "severity": 4 },
              { "id": "r5", "date": "2026-10-23T00:00:00.000Z", "kind": "reading", "label": "5/10", "severity": 5 },
              { "id": "r4", "date": "2026-10-16T00:00:00.000Z", "kind": "reading", "label": "6/10", "severity": 6 },
              { "id": "r3", "date": "2026-10-09T00:00:00.000Z", "kind": "reading", "label": "6/10", "severity": 6 },
              { "id": "r2", "date": "2026-10-02T00:00:00.000Z", "kind": "reading", "label": "7/10", "severity": 7 },
              { "id": "r1", "date": "2026-09-25T00:00:00.000Z", "kind": "reading", "label": "8/10", "severity": 8 } ] },
          { "id": "z2", "title": "Bas du dos", "category": "PAIN", "categoryLabel": "Raideur",
            "bodyPart": "Bas du dos", "side": "NA", "status": "ACTIVE", "statusLabel": "Active", "affectsTraining": true,
            "startDate": "2026-10-06T00:00:00.000Z", "strategy": "protect", "strategyLabel": "À protéger",
            "strategyDetail": "10 min de mobilité du dos après chaque sortie vélo de plus de 2 h.", "timeline": [] },
          { "id": "z3", "title": "Genou droit", "category": "INJURY", "categoryLabel": "Blessure", "bodyPart": "Genou",
            "side": "RIGHT", "sideLabel": "Droit", "status": "RESOLVED", "statusLabel": "Résolue", "affectsTraining": true,
            "startDate": "2026-04-01T00:00:00.000Z", "resolvedAt": "2026-06-12T00:00:00.000Z",
            "strategy": "none", "strategyLabel": "", "strategyDetail": "", "timeline": [] } ] }
        """#.utf8)
    }

    func updateNote(id: String, patch: PhysicalNotePatch, token: String) async throws {}
    func addCheckin(noteId: String, input: PhysicalCheckinInput, token: String) async throws {}
    func createNote(_ input: CreatePhysicalNoteInput, token: String) async throws {}
}

/// A race five weeks out with its projection, two figures in progress, one goal reached.
private struct DemoGoals: GoalServing {
    func goals(token: String) async throws -> [V1Goal] {
        let day = Calendar.current.date(byAdding: .day, value: 37, to: .now) ?? .now
        var race = V1Goal(title: "Triathlon M", kind: .race, targetDate: day)
        race.targetPerformance = "2 h 30"
        race.projection = V1RaceProjection(
            finishSec: 8_880, lowSec: 8_700, highSec: 9_100, targetSec: 9_000, deltaSec: -120,
            legs: [.init(kind: .swim, sec: 1_620), .init(kind: .t1, sec: 180), .init(kind: .bike, sec: 4_320), .init(kind: .t2, sec: 120), .init(kind: .run, sec: 2_640)],
            confidence: .high
        )
        var ftp = V1Goal(title: String(localized: "Seuil vélo à 280 W"), kind: .metric, targetDate: Calendar.current.date(byAdding: .month, value: 3, to: .now))
        ftp.startValue = 250; ftp.currentValue = 268; ftp.targetValue = 280; ftp.unit = "W"
        var done = V1Goal(title: String(localized: "Semi-marathon sous 1 h 32"), kind: .metric)
        done.achieved = true
        return [race, ftp, done]
    }

    func createGoal(_ input: CreateGoalInput, token: String) async throws -> V1Goal { V1Goal(title: "", kind: .metric) }
    func toggleAchieved(id: String, achieved: Bool, token: String) async throws -> V1Goal { V1Goal(title: "", kind: .metric) }
    func deleteGoal(id: String, token: String) async throws {}
    func updateGoal(id: String, fields: [String: JSONValue], token: String) async throws -> V1Goal { V1Goal(title: "", kind: .metric) }
    func achievements(limit: Int, token: String) async throws -> [V1GoalAchievement] { [] }
    func linkedActivities(goalId: String, token: String) async throws -> [V1GoalLinkedActivity] { [] }
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
                ], minutes: 3, source: "coach", optional: true)
            ),
            isKey: true
        )
    }
}
#endif

#if DEBUG
private struct GalleryWorkoutDockDemo: View {
    let session: GuidedStrengthSession?
    @State private var dock = GuidedWorkoutDock()

    var body: some View {
        TabView {
            Tab("Résumé", systemImage: "house") {
                NavigationStack { Text("Résumé").navigationTitle("Résumé") }
            }
            Tab("Plan", systemImage: "calendar") {
                NavigationStack { Text("Plan").navigationTitle("Plan") }
            }
        }
        .modifier(GuidedWorkoutDockHost(dock: dock))
        .task {
            guard let session else { return }
            dock.start(session, finish: GuidedStrengthFinishContext(
                client: ActivityClient(), linker: PlannedSessionClient(), tokenProvider: { "demo" }
            ))
        }
    }
}
#endif

/// A triathlete who also lifts at home, for Matériel.
private struct DemoEquipment: AthleteProfileServing {
    private static let profile = Data("""
    {"practicedSports":{"version":1,"sports":["triathlon","strength"]},
     "equipment":{"version":1,"strengthVenue":"home","owned":["bike_home_trainer","bike_power_meter","swim_pool","run_track"]}}
    """.utf8)

    func athleteProfile(token: String) async throws -> V1AthleteProfile {
        try JSONDecoder().decode(V1AthleteProfile.self, from: Self.profile)
    }

    func patchAthleteProfile(_ patch: AthleteProfilePatch, token: String) async throws -> V1AthleteProfile {
        try await athleteProfile(token: token)
    }

    func thresholdHistory(token: String) async throws -> [V1ThresholdSnapshot] { [] }
}

/// A lunch of four foods, read from an in-memory log.
private struct DemoMealPage: View {
    @State private var store = FoodLogStore(client: DemoFoodLog(), tokenProvider: { "demo" })

    var body: some View {
        FoodLogMealPage(store: store, meal: .lunch, flags: [])
            .task { await store.load(trainingDayId: TrainingDayId.today(now: .now)) }
    }
}

/// One day's log and nothing else: every write is refused, the demo is for reading the pages.
private struct DemoFoodLog: FoodLogServing {
    static let pasta = V1FoodProduct(
        id: "demo-pasta", source: "CIQUAL", name: String(localized: "Pâtes complètes, cuites"),
        kcalPer100g: 124, proteinPer100g: 4.8, carbsPer100g: 25, fatPer100g: 0.9, fiberPer100g: 3.6
    )

    func day(trainingDayId: String, token: String) async throws -> V1FoodLogDay {
        try JSONDecoder().decode(V1FoodLogDay.self, from: Data("""
        {"trainingDayId":"\(trainingDayId)","recent":[],"targets":{"mode":"GRAMS","kcal":2850,"proteinG":150,"carbsG":380,"fatG":90},
         "entries":[
          {"id":"1","meal":"LUNCH","name":"Riz basmati, cuit","grams":220,"kcal":286,"protein":6,"carbs":62,"fat":1},
          {"id":"2","meal":"LUNCH","name":"Blanc de poulet grillé","grams":150,"kcal":248,"protein":46,"carbs":0,"fat":5},
          {"id":"3","meal":"LUNCH","name":"Courgettes sautées","grams":180,"kcal":61,"protein":3,"carbs":6,"fat":3},
          {"id":"4","meal":"LUNCH","name":"Huile d'olive","grams":14,"kcal":126,"protein":0,"carbs":0,"fat":14}]}
        """.utf8))
    }

    func add(_ draft: FoodLogDraft, token: String) async throws -> V1FoodLogEntry { throw SharpitAPIError.server }
    func add(_ drafts: [FoodLogDraft], token: String) async throws -> [V1FoodLogEntry] { throw SharpitAPIError.server }
    func update(entryId: String, _ change: FoodLogEntryChange, token: String) async throws -> V1FoodLogEntry { throw SharpitAPIError.server }
    func delete(entryId: String, token: String) async throws { throw SharpitAPIError.server }
    func search(_ query: String, token: String) async throws -> V1FoodSearchResults { throw SharpitAPIError.server }
    func product(barcode: String, token: String) async throws -> V1FoodProduct? { nil }
    func createCustomFood(_ draft: FoodCustomDraft, token: String) async throws -> V1FoodProduct { throw SharpitAPIError.server }
    func ownFoods(token: String) async throws -> [V1FoodProduct] { [Self.pasta] }
    func updateCustomFood(id: String, _ draft: FoodCustomDraft, token: String) async throws -> V1FoodProduct { throw SharpitAPIError.server }
    func deleteCustomFood(id: String, token: String) async throws { throw SharpitAPIError.server }
    func setTargets(_ targets: V1NutritionTargets, trainingDayId: String, token: String) async throws -> V1NutritionTargets { targets }
    func setSkipped(_ meal: FoodLogMeal, skipped: Bool, trainingDayId: String, token: String) async throws -> [FoodLogMeal] { [] }
    func copy(from fromDayId: String, meal: FoodLogMeal?, to toDayId: String, token: String) async throws -> [V1FoodLogEntry] { [] }
    func savedMeals(token: String) async throws -> [V1SavedMeal] { [] }
    func saveMeal(name: String, trainingDayId: String, meal: FoodLogMeal, token: String) async throws -> V1SavedMeal { throw SharpitAPIError.server }
    func deleteSavedMeal(id: String, token: String) async throws { throw SharpitAPIError.server }
    func logSavedMeal(id: String, trainingDayId: String, meal: FoodLogMeal, token: String) async throws -> [V1FoodLogEntry] { [] }
    func saveRecipe(id: String?, _ draft: FoodRecipeDraft, token: String) async throws -> V1FoodProduct { throw SharpitAPIError.server }
    func describeMeal(_ description: String, token: String) async throws -> [V1DescribedFood] { [] }
}

private struct DemoTargetsSheet: View {
    @State private var store = FoodLogStore(client: DemoFoodLog(), tokenProvider: { "demo" })
    @State private var isLoaded = false

    var body: some View {
        Group {
            if isLoaded { NutritionTargetsSheet(store: store) }
        }
        .task {
            await store.load(trainingDayId: TrainingDayId.today(now: .now))
            isLoaded = true
        }
    }
}

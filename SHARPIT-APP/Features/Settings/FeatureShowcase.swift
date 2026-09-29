import SwiftUI

/// What a feature looks like, drawn by the very components the app shows it with, on example
/// figures — so the picture in Paramètres can never drift from the screen it describes.
struct FeatureShowcase: View {
    let feature: SharpitFeature

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            exampleBadge
            switch feature {
            case .journal: journal
            case .nutrition: nutrition
            case .health: health
            case .regularity: regularity
            }
        }
        .padding(SharpitSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            SharpitCanvasBackground()
                .clipShape(RoundedRectangle(cornerRadius: SharpitRadius.panelLarge, style: .continuous))
        )
    }

    /// Above the example, never over it: laid on top it hid the chevron of every card.
    private var exampleBadge: some View {
        Text("Exemple")
            .font(SharpitTypography.label)
            .tracking(SharpitTypography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(SharpitColor.mutedForeground)
            .padding(.horizontal, SharpitSpacing.xs)
            .padding(.vertical, 2)
            .background(SharpitColor.analysisSurfaceAlt, in: Capsule())
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var journal: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            Label("Journal", systemImage: "book.closed")
                .labelStyle(.titleAndIcon)
                .foregroundStyle(SharpitColor.foreground)
                .sharpitGlassChip()
                .padding(.bottom, SharpitSpacing.xs)
            JournalMetricRow(label: "Humeur", symbolName: "face.smiling", iconColor: SharpitColor.primary, value: "Bien") {}
            JournalFactorRow(label: "Alcool", symbolName: "wineglass", state: .no) { _ in }
            JournalFactorRow(label: "Écrans tard", symbolName: "iphone", state: .yes) { _ in }
        }
    }

    @ViewBuilder
    private var nutrition: some View {
        if let day = Self.nutritionDay {
            NutritionTodayCard(phase: .loaded(day)) {}
        }
    }

    private var health: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: SharpitSpacing.sm), GridItem(.flexible(), spacing: SharpitSpacing.sm)],
            spacing: SharpitSpacing.sm
        ) {
            SanteMarkerTile(marker: Self.marker(.restingHr, 47, from: 50, norm: ("Niveau athlète", .good), trend: .good)) {}
            SanteMarkerTile(marker: Self.marker(.hrv, 61, from: 57, norm: ("Dans ta plage habituelle", .good), trend: .good)) {}
            SanteMarkerTile(marker: Self.marker(.sleep, 412, from: 440, norm: ("Un peu court", .neutral), trend: .watch)) {}
            SanteMarkerTile(marker: Self.marker(.vo2max, 54, from: 53, norm: ("Bien au-dessus de ton âge", .good), trend: nil)) {}
        }
    }

    private var regularity: some View {
        ConsistencyStrip(consistency: Self.consistency)
    }

    // MARK: Example figures

    private static let nutritionDay: V1NutritionDay? = try? JSONDecoder().decode(V1NutritionDay.self, from: Data("""
    { "calories": 1480, "protein": 112, "carbohydrates": 165, "fat": 48, "fiber": 22, "sugar": null, "complete": false,
      "goals": {
        "calories": { "consumed": 1480, "goal": 2310, "remaining": 830, "pct": 64 },
        "protein": { "consumed": 112, "goal": 140, "remaining": 28, "pct": 80 },
        "carbohydrates": { "consumed": 165, "goal": 290, "remaining": 125, "pct": 57 },
        "fat": { "consumed": 48, "goal": 75, "remaining": 27, "pct": 64 },
        "exerciseCalories": 420, "calorieBudget": 2310 },
      "meals": [] }
    """.utf8))

    private static func marker(
        _ key: V1HealthMarker.Key,
        _ value: Double,
        from start: Double,
        norm: (label: String, tone: V1HealthTone),
        trend: V1HealthTone?
    ) -> V1HealthMarker {
        let now = Date.now
        let series = (0..<30).map { day in
            CorpsPoint(
                date: Calendar.current.date(byAdding: .day, value: day - 29, to: now) ?? now,
                value: start + (value - start) * Double(day) / 29 + sin(Double(day) / 3) * abs(value - start) * 0.2
            )
        }
        return V1HealthMarker(
            key: key,
            value: value,
            basis: .average7,
            measuredAt: now,
            norm: V1HealthNorm(band: "", label: norm.label, tone: norm.tone, reference: ""),
            trend: trend.map { V1HealthTrend(recent: value, baseline: start, delta: value - start, stable: false, tone: $0) },
            series: series
        )
    }

    private static var consistency: V1TodayConsistency {
        let calendar = Calendar.current
        let trained: Set<Int> = [-6, -5, -3, -1, 0]
        let days = (-6...1).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: .now) ?? .now
            return V1TodayConsistencyDay(
                date: TrainingDayId.today(now: day),
                weekdayLabel: day.sharpitFormatted(.dateTime.weekday(.narrow)),
                dayOfMonth: calendar.component(.day, from: day),
                hasActivity: trained.contains(offset),
                isToday: offset == 0,
                isFuture: offset > 0
            )
        }
        return V1TodayConsistency(days: days, thisWeekSessionCount: 4)
    }
}

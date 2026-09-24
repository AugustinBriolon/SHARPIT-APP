import Foundation

/// The metrics Corps shows, in the order of its sections.
///
/// Every key is one the web serves or will serve under the same name in
/// `/api/v1/body/overview` (see `docs/superpowers/specs/2026-09-24-ios-corps-parametres-pro-design.md`),
/// so moving Corps onto that endpoint changes where the values come from, not what they are.
nonisolated enum CorpsMetricKey: String, CaseIterable, Identifiable, Sendable {
    case weight
    case hrv
    case restingHr
    case vo2maxRun
    case vo2maxBike
    case bodyFatPct
    case leanMassKg
    case musclePct
    case waterPct
    case boneKg
    case bmi
    case visceralFat
    case bmr
    case bodyAgeScale
    case vascularAge
    case ftp
    case maxHr
    case lthr
    case runThresholdPace
    case swimCss

    var id: String { rawValue }

    var section: CorpsSection {
        switch self {
        case .weight: .hero
        case .hrv, .restingHr, .vo2maxRun, .vo2maxBike: .recovery
        case .bodyFatPct, .leanMassKg, .musclePct, .waterPct, .boneKg, .bmi,
             .visceralFat, .bmr, .bodyAgeScale, .vascularAge: .composition
        case .ftp, .maxHr, .lthr, .runThresholdPace, .swimCss: .thresholds
        }
    }

    var label: String {
        switch self {
        case .weight: "Poids"
        case .hrv: "VFC"
        case .restingHr: "FC de repos"
        case .vo2maxRun: "VO₂max course"
        case .vo2maxBike: "VO₂max vélo"
        case .bodyFatPct: "Masse grasse"
        case .leanMassKg: "Masse maigre"
        case .musclePct: "Muscle"
        case .waterPct: "Eau corporelle"
        case .boneKg: "Masse osseuse"
        case .bmi: "IMC"
        case .visceralFat: "Graisse viscérale"
        case .bmr: "Métabolisme de base"
        case .bodyAgeScale: "Âge corporel"
        case .vascularAge: "Âge vasculaire"
        case .ftp: "FTP"
        case .maxHr: "FC max"
        case .lthr: "FC seuil"
        case .runThresholdPace: "Allure seuil"
        case .swimCss: "CSS natation"
        }
    }

    var unit: String? {
        switch self {
        case .weight, .leanMassKg, .boneKg: "kg"
        case .hrv: "ms"
        case .restingHr, .maxHr, .lthr: "bpm"
        case .vo2maxRun, .vo2maxBike: "ml/kg/min"
        case .bodyFatPct, .musclePct, .waterPct: "%"
        case .bmi, .visceralFat: nil
        case .bmr: "kcal"
        case .bodyAgeScale, .vascularAge: "ans"
        case .ftp: "W"
        case .runThresholdPace: "/km"
        case .swimCss: "/100 m"
        }
    }

    /// What the number is, in one sentence, under the drawer's chart. Descriptive, never a
    /// verdict: SHARPIT does not know what the athlete is aiming for.
    var explanation: String {
        switch self {
        case .weight:
            "Chaque point est une pesée. Une variation d'un jour à l'autre est surtout de l'eau."
        case .hrv:
            "Variabilité de la fréquence cardiaque mesurée la nuit par ta montre. La bande est ta plage habituelle selon Garmin."
        case .restingHr:
            "Fréquence cardiaque la plus basse de la nuit. Une hausse durable accompagne souvent la fatigue ou la maladie."
        case .vo2maxRun, .vo2maxBike:
            "Estimation de ta capacité aérobie par ta montre, à partir de tes séances."
        case .bodyFatPct, .musclePct, .waterPct, .boneKg, .bmi:
            "Mesuré par ta balance. Suis la tendance plutôt qu'une pesée isolée."
        case .leanMassKg:
            "Tout ce qui n'est pas de la graisse : muscles, os, organes et eau."
        case .visceralFat:
            "Indice de la graisse autour des organes, estimé par ta balance."
        case .bmr:
            "L'énergie que ton corps dépense au repos sur une journée, estimée par ta balance."
        case .bodyAgeScale:
            "L'âge que ta balance associe à ta composition corporelle. Une estimation du fabricant, pas un âge biologique."
        case .vascularAge:
            "Estimé par ta balance à partir de la vitesse de l'onde de pouls. Une indication, pas un diagnostic."
        case .ftp, .lthr, .runThresholdPace, .swimCss:
            "Chaque point est une valeur enregistrée — importée de Garmin, estimée ou saisie."
        case .maxHr:
            "La fréquence la plus haute que ton cœur atteint. Elle sert à caler tes zones."
        }
    }
}

nonisolated enum CorpsSection: String, CaseIterable, Sendable {
    case hero
    case recovery
    case composition
    case thresholds

    var title: String {
        switch self {
        case .hero: "Poids"
        case .recovery: "Récupération"
        case .composition: "Composition"
        case .thresholds: "Seuils"
        }
    }
}

nonisolated struct CorpsPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let value: Double

    var id: Date { date }
}

/// One metric as Corps shows it: the latest value, how it reads against its reference, and the
/// series behind it for the drawer.
nonisolated struct CorpsMetric: Identifiable, Equatable, Sendable {
    let key: CorpsMetricKey
    let value: Double
    let measuredAt: Date?
    let source: String?
    /// Oldest first, as a time axis reads them.
    let series: [CorpsPoint]
    /// The athlete's usual band, when the source defines one (Garmin's HRV baseline).
    let baseline: ClosedRange<Double>?
    /// A short reading beside the value — a change or where it sits in the band.
    let note: String?
    let tone: CorpsTone

    var id: String { key.rawValue }

    var formattedValue: String { CorpsReadout.format(value, for: key) }
}

/// Colour only for a semantic state (`docs/adr/0004`): a reading inside or outside a band.
/// Changes with no known direction — a kilo up or down — stay neutral.
nonisolated enum CorpsTone: Equatable, Sendable {
    case neutral
    case inRange
    case belowRange
}

nonisolated enum CorpsReadout {
    /// A change under this is the scale repeating itself, not a trend.
    static let weightNoiseKg = 0.2

    static func metrics(
        profile: V1AthleteProfile?,
        measurements: [V1BodyMeasurement],
        recovery: V1RecoveryResponse?,
        thresholds: [V1ThresholdSnapshot]
    ) -> [CorpsMetric] {
        var metrics: [CorpsMetric] = []
        let weighIns = measurements.sorted { $0.measuredAt < $1.measuredAt }

        func scale(_ key: CorpsMetricKey, _ read: (V1BodyMeasurement) -> Double?) {
            let series = weighIns.compactMap { m in read(m).flatMap { $0 > 0 ? CorpsPoint(date: m.measuredAt, value: $0) : nil } }
            guard let last = series.last else { return }
            let source = weighIns.last { read($0) != nil }?.source
            metrics.append(CorpsMetric(
                key: key,
                value: last.value,
                measuredAt: last.date,
                source: BodyCompositionReadout.scaleLabel(source),
                series: series,
                baseline: nil,
                note: key == .weight ? weightChange(series) : nil,
                tone: .neutral
            ))
        }

        scale(.weight) { $0.weightKg }
        recoveryMetrics(recovery).forEach { metrics.append($0) }
        if let run = profile?.vo2maxRunning {
            metrics.append(single(.vo2maxRun, Double(run), source: "Garmin"))
        }
        if let bike = profile?.vo2maxCycling {
            metrics.append(single(.vo2maxBike, Double(bike), source: "Garmin"))
        }
        scale(.bodyFatPct) { $0.bodyFatPct }
        scale(.leanMassKg) { m in
            guard let weight = m.weightKg, let fat = m.bodyFatPct, fat > 0, fat < 100 else { return nil }
            return weight * (1 - fat / 100)
        }
        scale(.musclePct) { $0.musclePct }
        scale(.waterPct) { $0.waterPct }
        scale(.boneKg) { $0.boneKg }
        scale(.bmi) { $0.bmi }

        let snapshots = thresholds.sorted { $0.createdAt < $1.createdAt }
        func threshold(_ key: CorpsMetricKey, current: Double?, _ read: (V1ThresholdSnapshot) -> Double?) {
            guard let current, current > 0 else { return }
            let series = snapshots.compactMap { s in read(s).map { CorpsPoint(date: s.createdAt, value: $0) } }
            metrics.append(CorpsMetric(
                key: key,
                value: current,
                measuredAt: profile?.thresholdsSyncedAt ?? series.last?.date,
                source: snapshots.last { read($0) != nil }?.sourceLabel,
                series: series,
                baseline: nil,
                note: nil,
                tone: .neutral
            ))
        }
        threshold(.ftp, current: profile?.ftpW.map(Double.init)) { $0.ftpW.map(Double.init) }
        if let maxHr = profile?.maxHr {
            metrics.append(single(.maxHr, Double(maxHr), source: nil))
        }
        threshold(.lthr, current: profile?.lthr.map(Double.init)) { $0.lthr.map(Double.init) }
        threshold(.runThresholdPace, current: profile?.runThresholdPaceSecPerKm) { $0.runThresholdPaceSecPerKm }
        threshold(.swimCss, current: profile?.swimCssSecPer100m) { $0.swimCssSecPer100m }

        return metrics
    }

    /// The web's overview, as Corps shows it: the value, its reference, and the one reading
    /// beside it — the band for HRV, the change over the window for the rest.
    static func metrics(from overview: V1BodyOverview) -> [CorpsMetric] {
        let byKey = Dictionary(overview.metrics.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return CorpsMetricKey.allCases.compactMap { key in
            guard let metric = byKey[key] else { return nil }
            let band = metric.baseline.flatMap { $0.low <= $0.high ? $0.low...$0.high : nil }
            return CorpsMetric(
                key: key,
                value: metric.value,
                measuredAt: metric.measuredAt,
                source: sourceLabel(metric.source),
                series: [],
                baseline: band,
                note: note(for: metric, band: band),
                tone: tone(for: metric, band: band)
            )
        }
    }

    /// The overview's values, each carrying the series the app assembled for the same key, so a
    /// tile keeps its small trend. A metric only the app knows is dropped: the web decides
    /// what Corps shows.
    static func merging(overview: V1BodyOverview, localSeries local: [CorpsMetric]) -> [CorpsMetric] {
        let seriesByKey = Dictionary(local.map { ($0.key, $0.series) }, uniquingKeysWith: { first, _ in first })
        return metrics(from: overview).map { metric in
            CorpsMetric(
                key: metric.key,
                value: metric.value,
                measuredAt: metric.measuredAt,
                source: metric.source,
                series: seriesByKey[metric.key] ?? [],
                baseline: metric.baseline,
                note: metric.note,
                tone: metric.tone
            )
        }
    }

    /// A series from the web, oldest first, as points on a time axis.
    static func points(from series: V1BodySeries) -> [CorpsPoint] {
        series.points.compactMap { point in
            TrainingDayId.date(point.date).map { CorpsPoint(date: $0, value: point.value) }
        }
    }

    static func sourceLabel(_ source: String) -> String? {
        switch source.lowercased() {
        case "withings": "Withings"
        case "garmin": "Garmin"
        case "renpho": "Renpho"
        case "apple_health", "apple-health": "Apple Santé"
        case "profile", "manual": "Saisi"
        case "estimated": "Estimé"
        case "": nil
        default: source.capitalized
        }
    }

    private static func note(for metric: V1BodyMetric, band: ClosedRange<Double>?) -> String? {
        if metric.key == .hrv, let band {
            return "plage \(Int(band.lowerBound.rounded()))–\(Int(band.upperBound.rounded()))"
        }
        guard let previous = metric.previous, let days = metric.deltaWindowDays else { return nil }
        let delta = metric.value - previous
        let noise = metric.key == .weight ? weightNoiseKg : 0.05 * max(abs(previous), 1)
        if abs(delta) < noise { return "stable sur \(days) j" }
        let sign = delta > 0 ? "+" : "−"
        let unit = metric.key.unit.map { " \($0)" } ?? ""
        return "\(sign)\(format(abs(delta), for: metric.key))\(unit) sur \(days) j"
    }

    private static func tone(for metric: V1BodyMetric, band: ClosedRange<Double>?) -> CorpsTone {
        guard metric.key == .hrv, let band else { return .neutral }
        return metric.value < band.lowerBound ? .belowRange : .inRange
    }

    /// HRV and resting HR from the recovery read: the nights it carries, and today's.
    static func recoveryMetrics(_ recovery: V1RecoveryResponse?) -> [CorpsMetric] {
        guard let recovery else { return [] }
        var nights: [(Date, Double?, Double?)] = recovery.history.compactMap { day in
            TrainingDayId.date(day.date).map { ($0, day.hrv, day.restingHr) }
        }
        if let today = TrainingDayId.date(recovery.trainingDayId),
           !nights.contains(where: { Calendar.current.isDate($0.0, inSameDayAs: today) }) {
            nights.append((today, recovery.today.hrv, recovery.today.restingHr))
        }
        nights.sort { $0.0 < $1.0 }

        var metrics: [CorpsMetric] = []
        let hrvSeries = nights.compactMap { night in night.1.map { CorpsPoint(date: night.0, value: $0) } }
        if let last = hrvSeries.last {
            var band: ClosedRange<Double>?
            if let low = recovery.today.hrvBaselineLow, let high = recovery.today.hrvBaselineHigh, low <= high {
                band = low...high
            }
            metrics.append(CorpsMetric(
                key: .hrv,
                value: last.value,
                measuredAt: last.date,
                source: "Garmin",
                series: hrvSeries,
                baseline: band,
                note: band.map { "plage \(Int($0.lowerBound.rounded()))–\(Int($0.upperBound.rounded()))" },
                tone: band.map { band -> CorpsTone in
                    last.value < band.lowerBound ? .belowRange : .inRange
                } ?? .neutral
            ))
        }
        let rhrSeries = nights.compactMap { night in night.2.map { CorpsPoint(date: night.0, value: $0) } }
        if let last = rhrSeries.last {
            metrics.append(CorpsMetric(
                key: .restingHr,
                value: last.value,
                measuredAt: last.date,
                source: "Garmin",
                series: rhrSeries,
                baseline: nil,
                note: mean(rhrSeries).map { "moyenne \(Int($0.rounded())) bpm" },
                tone: .neutral
            ))
        }
        return metrics
    }

    /// The latest weight against a weigh-in at least a week older — two consecutive mornings
    /// differ by water, not composition.
    static func weightChange(_ series: [CorpsPoint]) -> String? {
        guard let last = series.last else { return nil }
        let cutoff = last.date.addingTimeInterval(-7 * 24 * 3600)
        guard let reference = series.last(where: { $0.date <= cutoff }) else { return nil }
        let delta = last.value - reference.value
        guard abs(delta) >= weightNoiseKg else { return "stable sur 7 j" }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(ProfileFieldFormat.decimal(abs(delta))) kg sur 7 j"
    }

    static func format(_ value: Double, for key: CorpsMetricKey) -> String {
        switch key {
        case .runThresholdPace, .swimCss:
            ProfileFieldFormat.pace(value)
        case .hrv, .restingHr, .vo2maxRun, .vo2maxBike, .ftp, .maxHr, .lthr:
            String(Int(value.rounded()))
        case .bmr, .bodyAgeScale, .vascularAge, .visceralFat:
            String(Int(value.rounded()))
        case .weight, .leanMassKg, .boneKg, .bodyFatPct, .musclePct, .waterPct, .bmi:
            ProfileFieldFormat.decimal(value)
        }
    }

    private static func single(_ key: CorpsMetricKey, _ value: Double, source: String?) -> CorpsMetric {
        CorpsMetric(
            key: key,
            value: value,
            measuredAt: nil,
            source: source,
            series: [],
            baseline: nil,
            note: nil,
            tone: .neutral
        )
    }

    private static func mean(_ points: [CorpsPoint]) -> Double? {
        guard points.count > 1 else { return nil }
        return points.map(\.value).reduce(0, +) / Double(points.count)
    }
}

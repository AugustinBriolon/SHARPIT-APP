import AppIntents
import SwiftUI
import WidgetKit

/// The sport a « Volume de la semaine » widget counts, chosen when it is added or edited.
enum VolumeSport: String, AppEnum {
    case all, run, bike, swim, hike, strength

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Sport"
    static let caseDisplayRepresentations: [VolumeSport: DisplayRepresentation] = [
        .all: "Tous les sports",
        .run: "Course",
        .bike: "Vélo",
        .swim: "Natation",
        .hike: "Randonnée",
        .strength: "Force",
    ]

    var activityType: V1ActivityType? {
        switch self {
        case .all: nil
        case .run: .run
        case .bike: .bike
        case .swim: .swim
        case .hike: .hike
        case .strength: .strength
        }
    }
}

struct VolumeConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Volume de la semaine"
    static let description = IntentDescription("Le sport compté par le widget.")

    @Parameter(title: "Sport", default: .run)
    var sport: VolumeSport
}

struct VolumeEntry: TimelineEntry {
    let date: Date
    let training: WidgetSnapshot.Training?
    let sport: VolumeSport

    var volume: WeekVolume? { training?.week(of: date, sport: sport.activityType) }
}

/// Reads the snapshot for the sport the widget was set to; redrawn at midnight, when the
/// week's day turns — and on Monday, when the week does.
struct VolumeProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> VolumeEntry {
        VolumeEntry(date: .now, training: WidgetSnapshot.preview.training, sport: .run)
    }

    func snapshot(for configuration: VolumeConfiguration, in context: Context) async -> VolumeEntry {
        let training = context.isPreview ? WidgetSnapshot.preview.training : WidgetSnapshotStore.read()?.training
        return VolumeEntry(date: .now, training: training, sport: configuration.sport)
    }

    func timeline(for configuration: VolumeConfiguration, in _: Context) async -> Timeline<VolumeEntry> {
        let now = Date.now
        let training = WidgetSnapshotStore.read()?.training
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        return Timeline(
            entries: [
                VolumeEntry(date: now, training: training, sport: configuration.sport),
                VolumeEntry(date: midnight, training: training, sport: configuration.sport),
            ],
            policy: .after(midnight)
        )
    }
}

/// « Volume de la semaine »: what was done this week in the sport it counts — kilometres, or
/// time where kilometres say nothing — its sessions, and a bar per day.
struct VolumeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "WeekVolume", intent: VolumeConfiguration.self, provider: VolumeProvider()) { entry in
            VolumeWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetCanvas() }
                .widgetURL(WidgetSnapshot.link("/activity"))
        }
        .configurationDisplayName("Volume de la semaine")
        .description("Tes kilomètres ou ton temps de la semaine, par sport.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct VolumeWidgetView: View {
    let entry: VolumeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label(entry.sport.title, systemImage: entry.sport.symbolName)
                    .font(.caption)
                    .widgetAccentable()
                if let volume = entry.volume {
                    Text("\(volume.figureText) \(volume.unit)")
                        .font(.headline.monospacedDigit())
                    Text(volume.detailLine).font(.caption).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium:
            VolumeMedium(entry: entry)
        default:
            VolumeSmall(entry: entry)
        }
    }
}

struct VolumeSmall: View {
    let entry: VolumeEntry

    var body: some View {
        WidgetFrame(entry.sport.shortTitle, symbol: entry.sport.symbolName, tint: entry.sport.tone) {
            if let volume = entry.volume {
                WidgetHero(value: volume.figureText, unit: volume.unit)
                WidgetCaption(text: volume.detailLine)
                    .padding(.bottom, 8)
                WeekBars(volume: volume, tone: entry.sport.tone, height: 22, showsInitials: false)
            } else {
                WidgetAwaitingData(text: "Ouvre Activité pour charger ta semaine.")
            }
        }
    }
}

struct VolumeMedium: View {
    let entry: VolumeEntry

    var body: some View {
        WidgetFrame(entry.sport.title, symbol: entry.sport.symbolName, tint: entry.sport.tone) {
            if let volume = entry.volume {
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        WidgetHero(value: volume.figureText, unit: volume.unit)
                        WidgetCaption(text: volume.detailLine)
                        WidgetCaption(text: volume.lastWeekLine, lines: 2)
                            .padding(.top, WidgetMetrics.lineGap)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    WeekBars(volume: volume, tone: entry.sport.tone, height: 72, showsInitials: true)
                        .frame(width: 136)
                }
            } else {
                WidgetAwaitingData(text: "Ouvre Activité pour charger ta semaine.")
            }
        }
    }
}

/// A bar per day, Monday first, in the sport's color: a day trained stands, a rest day is a
/// tick, the days ahead are faint. Today carries a dot under it.
private struct WeekBars: View {
    let volume: WeekVolume
    let tone: Color
    let height: CGFloat
    let showsInitials: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: showsInitials ? 6 : 4) {
            ForEach(volume.days) { day in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(fill(day))
                        .frame(height: barHeight(day))
                        .frame(height: height, alignment: .bottom)
                        .widgetAccentable()
                    if showsInitials {
                        Text(day.initial)
                            .font(SharpitTypography.label)
                            .foregroundStyle(day.isToday ? SharpitColor.foreground : SharpitColor.mutedForeground)
                    }
                    Circle()
                        .fill(day.isToday ? SharpitColor.foreground : .clear)
                        .frame(width: 3, height: 3)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jours de la semaine")
    }

    private func barHeight(_ day: WeekVolume.Day) -> CGFloat {
        guard day.value > 0, volume.peakDay > 0 else { return 3 }
        return max(6, height * CGFloat(day.value / volume.peakDay))
    }

    private func fill(_ day: WeekVolume.Day) -> Color {
        if day.value > 0 { return tone }
        return SharpitColor.mutedForeground.opacity(day.isFuture ? 0.12 : 0.28)
    }
}

extension VolumeSport {
    var title: String {
        switch self {
        case .all: "Semaine"
        case .run: "Course · semaine"
        case .bike: "Vélo · semaine"
        case .swim: "Natation · semaine"
        case .hike: "Rando · semaine"
        case .strength: "Force · semaine"
        }
    }

    /// The small widget's header: the sport alone, the week being said by the bars.
    var shortTitle: String { activityType?.label ?? "Tous sports" }

    var symbolName: String { activityType?.symbolName ?? "figure.mixed.cardio" }

    var tone: Color { activityType.map { SharpitSportColor.color($0.identity) } ?? SharpitColor.primary }
}

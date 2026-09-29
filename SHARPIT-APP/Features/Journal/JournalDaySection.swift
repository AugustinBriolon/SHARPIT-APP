import SwiftUI

/// One tile of « Ta journée »: a figure and the line under it.
struct JournalDayTile: Equatable, Identifiable {
    enum Kind: String { case night, recovery, movement, sessions, energy }
    enum Destination { case sleep, recovery }

    let kind: Kind
    let title: String
    let symbol: String
    let value: String
    let caption: String?
    let destination: Destination?

    var id: Kind { kind }

    static func == (lhs: JournalDayTile, rhs: JournalDayTile) -> Bool {
        lhs.kind == rhs.kind && lhs.value == rhs.value && lhs.caption == rhs.caption
    }
}

/// How the journal reads a day's values — pure, so the wording is tested.
enum JournalDayReadout {
    private static let french = Locale(identifier: "fr_FR")

    static func hasAny(_ day: V1JournalDayData) -> Bool { !tiles(day).isEmpty }

    /// Only what was measured: a tile with nothing behind it is left out, never shown as zero.
    static func tiles(_ day: V1JournalDayData) -> [JournalDayTile] {
        var tiles: [JournalDayTile] = []
        if let minutes = day.sleep.minutes, minutes > 0 {
            var window: String?
            if let bed = day.sleep.bedtimeMin, let wake = day.sleep.wakeMin {
                window = "\(clock(bed)) → \(clock(wake))"
            }
            tiles.append(JournalDayTile(
                kind: .night, title: "Nuit", symbol: "moon.zzz",
                value: duration(minutes),
                caption: [day.sleep.score.map { "Score \($0)" }, window].compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                destination: .sleep
            ))
        }
        if day.hrv != nil || day.restingHr != nil {
            let value = day.hrv.map { "\($0) ms" } ?? day.restingHr.map { "\($0) bpm" } ?? ""
            let caption = [
                day.hrv != nil ? day.restingHr.map { "FC repos \($0)" } : nil,
                day.readiness.map { "Disponibilité \($0)" },
            ].compactMap { $0 }.joined(separator: " · ")
            tiles.append(JournalDayTile(
                kind: .recovery, title: day.hrv != nil ? "VFC" : "FC repos", symbol: "heart",
                value: value, caption: caption.nilIfEmpty, destination: .recovery
            ))
        }
        if let steps = day.steps, steps > 0 {
            tiles.append(JournalDayTile(
                kind: .movement, title: "Pas", symbol: "figure.walk",
                value: steps.formatted(.number.locale(french)),
                caption: day.napMinutes.flatMap { $0 > 0 ? "Sieste \(duration($0))" : nil },
                destination: nil
            ))
        }
        if day.activities.count > 0 {
            tiles.append(JournalDayTile(
                kind: .sessions, title: "Séances", symbol: "figure.run",
                value: day.activities.count == 1 ? "1 séance" : "\(day.activities.count) séances",
                caption: day.activities.minutes > 0 ? duration(day.activities.minutes) : nil,
                destination: nil
            ))
        }
        if day.stress != nil || day.bodyBattery != nil {
            tiles.append(JournalDayTile(
                kind: .energy, title: day.stress != nil ? "Stress" : "Body Battery", symbol: "waveform.path.ecg",
                value: day.stress.map { "\($0)" } ?? day.bodyBattery.map { "\($0)" } ?? "",
                caption: day.stress != nil ? day.bodyBattery.map { "Body Battery \($0)" } : nil,
                destination: nil
            ))
        }
        return tiles
    }

    /// « 7 h 12 », « 45 min ».
    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    /// Minutes after midnight as « 23:10 ».
    static func clock(_ minutes: Int) -> String {
        let wrapped = ((minutes % 1_440) + 1_440) % 1_440
        return String(format: "%d:%02d", wrapped / 60, wrapped % 60)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// « Ta journée »: what the devices measured on the day the journal is open on — the night,
/// recovery, movement, sessions, stress. Read-only; the night and recovery open their own day.
struct JournalDaySection<Destination: View>: View {
    let day: V1JournalDayData
    @ViewBuilder let destination: (JournalDayTile.Destination) -> Destination

    private var tiles: [JournalDayTile] { JournalDayReadout.tiles(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitEyebrow("Ta journée")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: SharpitSpacing.sm), GridItem(.flexible(), spacing: SharpitSpacing.sm)],
                spacing: SharpitSpacing.sm
            ) {
                ForEach(tiles) { tile in
                    if let target = tile.destination {
                        NavigationLink { destination(target) } label: { JournalDayTileView(tile: tile, opens: true) }
                            .buttonStyle(.sharpitPressable)
                    } else {
                        JournalDayTileView(tile: tile, opens: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JournalDayTileView: View {
    let tile: JournalDayTile
    let opens: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xs) {
            SharpitCardHeader(title: tile.title, symbol: tile.symbol, showsChevron: opens)
            Text(tile.value)
                .font(SharpitTypography.data)
                .tracking(SharpitTypography.dataTracking)
                .foregroundStyle(SharpitColor.foreground)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(tile.caption ?? " ")
                .font(SharpitTypography.meta.monospacedDigit())
                .foregroundStyle(SharpitColor.mutedForeground)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .accessibilityElement(children: .combine)
    }
}

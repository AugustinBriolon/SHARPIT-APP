import SwiftUI

/// The paywall's opening picture: a week of sessions on the ink band, so Pro reads as « your week,
/// written » before a word. The onboarding passes the week the coach just wrote; elsewhere an
/// example week moves one session a day later, once, on arrival — the plan adapting.
struct ProWeekHero: View {
    /// The onboarding's preview week; nil draws the example.
    var sessions: [V1GeneratedSession]?

    @State private var hasAppeared = false
    @State private var hasAdapted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 34

    private struct Slot: Identifiable {
        let id: Int
        let day: Int
        let type: V1ActivityType
    }

    private static let example: [(day: Int, type: V1ActivityType)] = [
        (0, .run), (1, .swim), (3, .bike), (5, .run), (6, .bike),
    ]
    /// The example's Tuesday swim, moved to Wednesday.
    private static let adaptedIndex = 1
    private static let exampleMonday = TrainingDayId.date("2026-10-19") ?? .now
    private static let tileGap: CGFloat = 6

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = SharpitLocale.current
        return calendar
    }

    /// The band's first column: the week's first session, or the example's Monday.
    private var start: Date {
        sessions?.compactMap { TrainingDayId.date($0.date) }.min() ?? Self.exampleMonday
    }

    private var slots: [Slot] {
        guard let sessions else {
            return Self.example.enumerated().map { index, entry in
                let moved = index == Self.adaptedIndex && hasAdapted
                return Slot(id: index, day: entry.day + (moved ? 1 : 0), type: entry.type)
            }
        }
        return sessions.enumerated().compactMap { index, session in
            guard let date = TrainingDayId.date(session.date) else { return nil }
            let day = calendar.dateComponents([.day], from: start, to: date).day ?? 0
            return Slot(id: index, day: min(max(day, 0), 6), type: session.type)
        }
    }

    var body: some View {
        let slots = slots
        VStack(spacing: SharpitSpacing.sm) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { day in
                    Text(letter(day))
                        .font(SharpitTypography.label)
                        .foregroundStyle(SharpitColor.inkSurfaceForeground.opacity(0.55))
                        .frame(maxWidth: .infinity)
                }
            }
            GeometryReader { proxy in
                let column = proxy.size.width / 7
                ZStack(alignment: .topLeading) {
                    ForEach(0..<7, id: \.self) { day in
                        RoundedRectangle(cornerRadius: SharpitRadius.small, style: .continuous)
                            .fill(SharpitColor.inkSurfaceForeground.opacity(0.06))
                            .frame(width: column - 6, height: proxy.size.height)
                            .offset(x: column * CGFloat(day) + 3)
                    }
                    ForEach(slots) { slot in
                        tile(slot.type)
                            .scaleEffect(hasAppeared ? 1 : 0.6)
                            .opacity(hasAppeared ? 1 : 0)
                            .animation(SharpitMotion.reveal.delay(0.12 + SharpitMotion.staggerDelay(index: slot.id)), value: hasAppeared)
                            .position(
                                x: column * (CGFloat(slot.day) + 0.5),
                                y: tileSize / 2 + 4 + CGFloat(stackIndex(of: slot, in: slots)) * (tileSize + Self.tileGap)
                            )
                    }
                }
            }
            .frame(height: tileSize * 2 + Self.tileGap + 8)
        }
        .padding(SharpitSpacing.md)
        .frame(maxWidth: .infinity)
        .sharpitSurface(.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(slots.count) séances dans la semaine"))
        .onAppear { hasAppeared = true }
        .task {
            guard sessions == nil, !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(1.1))
            withAnimation(.spring(response: 0.5, dampingFraction: 1)) { hasAdapted = true }
        }
    }

    /// A lime squircle with the sport's ink glyph: on the ink band an ink tile would vanish.
    private func tile(_ type: V1ActivityType) -> some View {
        Image(sharpitSymbol: type.symbolName)
            .font(.system(size: tileSize * 0.44, weight: .bold))
            .foregroundStyle(SharpitColor.highlightForeground)
            .frame(width: tileSize, height: tileSize)
            .background(
                SharpitColor.highlight,
                in: RoundedRectangle(cornerRadius: SharpitRadius.tile * tileSize / SharpitTokens.tileSize, style: .continuous)
            )
    }

    /// Two sessions on one day stack: the second sits under the first.
    private func stackIndex(of slot: Slot, in slots: [Slot]) -> Int {
        min(slots.filter { $0.day == slot.day && $0.id < slot.id }.count, 1)
    }

    private func letter(_ day: Int) -> String {
        guard let date = calendar.date(byAdding: .day, value: day, to: start) else { return "" }
        return date.sharpitFormatted(.dateTime.weekday(.narrow))
    }
}

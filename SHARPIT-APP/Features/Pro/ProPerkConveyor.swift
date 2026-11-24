import SwiftUI

/// One thing SharpIt Pro adds, as the paywall says it: a glyph in a pillar's hue and one sentence.
/// The ids are the server's (`pro-perks.ts` in SHARPIT-WEBAPP), whose longer copy Réglages › Pro reads.
nonisolated struct ProPerkLine: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let pillar: CliniquePillar
    let sentence: String

    static let all: [ProPerkLine] = [
        ProPerkLine(id: "coach", symbol: "bubble.left", pillar: .coach, sentence: String(localized: "Un coach qui répond avec ta nuit, ta charge et ton plan")),
        ProPerkLine(id: "adaptive-plan", symbol: "calendar", pillar: .recovery, sentence: String(localized: "Un plan qui s'ajuste quand ta forme ou ton agenda change")),
        ProPerkLine(id: "weekly-review", symbol: "chart.bar", pillar: .sleep, sentence: String(localized: "Le bilan de ta semaine, et la suivante déjà prête")),
        ProPerkLine(id: "session-analysis", symbol: "figure.run", pillar: .recovery, sentence: String(localized: "Chaque séance lue : ce qui a marché, ce qui a coûté")),
        ProPerkLine(id: "journal-coach-read", symbol: "checklist", pillar: .coach, sentence: String(localized: "Tes habitudes analysées, un ou deux ajustements à tester")),
        ProPerkLine(id: "nutrition-reading", symbol: "flame", pillar: .nutrition, sentence: String(localized: "Ta nutrition lue chaque jour face à ton entraînement")),
        ProPerkLine(id: "biological-age", symbol: "heart", pillar: .sleep, sentence: String(localized: "Ton âge biologique, estimé depuis ta VO₂max")),
        ProPerkLine(id: "watch-push", symbol: "applewatch", pillar: .recovery, sentence: String(localized: "Tes séances envoyées sur ta montre")),
        ProPerkLine(id: "extra-widgets", symbol: "square.grid.2x2", pillar: .sleep, sentence: String(localized: "Sommeil, poids, volume et régularité sur ton écran d'accueil")),
        ProPerkLine(id: "early-access", symbol: "clock.badge.checkmark", pillar: .coach, sentence: String(localized: "Les nouveautés chez toi avant tout le monde")),
        ProPerkLine(id: "support", symbol: "hand.raised", pillar: .nutrition, sentence: String(localized: "SharpIt sans publicité ni revente de données, grâce à toi")),
    ]
}

/// Where a list that repeats without end stands: pure, so the motion is a function of the clock.
nonisolated enum ConveyorLoop {
    /// Points a second the list rises by itself: slow enough to read a line as it passes.
    static let speed: Double = 22
    /// How long a flick's speed takes to die down.
    static let flingDecay: Double = 0.35
    static let maxFling: Double = 1_600

    /// The offset brought back into one length of the list, whichever way it was dragged.
    static func wrapped(_ offset: Double, length: Double) -> Double {
        guard length > 0 else { return 0 }
        let remainder = offset.truncatingRemainder(dividingBy: length)
        return remainder < 0 ? remainder + length : remainder
    }

    /// The offset `elapsed` seconds after the finger left at `fling` points a second: the flick's
    /// travel dies down as the steady rise carries on, so the list never stops then starts.
    static func offset(from anchor: Double, elapsed: Double, fling: Double) -> Double {
        let time = max(elapsed, 0)
        let thrown = min(max(fling, -maxFling), maxFling)
        return anchor + speed * time + thrown * flingDecay * (1 - exp(-time / flingDecay))
    }
}

/// Everything Pro adds, rising without end under the paywall's title; the finger can take the
/// list either way and it carries on from there (the athlete's request, 2026-11-24). Under
/// Reduce Motion or at the accessibility text sizes it is the plain list.
struct ProPerkConveyor: View {
    var perks: [ProPerkLine] = ProPerkLine.all

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .callout) private var rowHeight: CGFloat = 58
    @State private var anchor: Double = 0
    @State private var anchoredAt = Date.now
    @State private var fling: Double = 0
    /// Where the list stood when the finger landed; nil while it runs by itself.
    @State private var dragOrigin: Double?
    @State private var dragTravel: Double = 0

    private static let visibleRows: CGFloat = 4.5

    var body: some View {
        if reduceMotion || typeSize.isAccessibilitySize {
            list
        } else {
            conveyor
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(perks) { perk in
                CliniqueDivider()
                ProPerkRow(perk: perk).padding(.vertical, 13)
            }
        }
    }

    private var conveyor: some View {
        let length = Double(rowHeight) * Double(perks.count)
        return TimelineView(.animation(paused: dragOrigin != nil)) { context in
            let offset = ConveyorLoop.wrapped(position(at: context.date), length: length)
            // Two copies, so the window is always full whatever part of the list it shows.
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { _ in
                    ForEach(perks) { perk in
                        ProPerkRow(perk: perk).frame(height: rowHeight)
                    }
                }
            }
            .offset(y: -offset)
            .frame(height: rowHeight * Self.visibleRows, alignment: .top)
        }
        .clipped()
        // The lines come out of the sheet and go back into it, never cut by an edge.
        .mask {
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14),
                        .init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .contentShape(.rect)
        .highPriorityGesture(drag)
        .accessibilityRepresentation { list }
    }

    private func position(at date: Date) -> Double {
        if let dragOrigin { return dragOrigin - dragTravel }
        return ConveyorLoop.offset(from: anchor, elapsed: date.timeIntervalSince(anchoredAt), fling: fling)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = position(at: .now) }
                dragTravel = value.translation.height
            }
            .onEnded { value in
                anchor = (dragOrigin ?? anchor) - value.translation.height
                anchoredAt = .now
                fling = -value.velocity.height
                dragOrigin = nil
                dragTravel = 0
            }
    }
}

private struct ProPerkRow: View {
    let perk: ProPerkLine

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: perk.symbol)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(perk.pillar.color)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(perk.sentence)
                .font(SharpitTypography.system(size: 16, weight: .semibold, relativeTo: .callout))
                .foregroundStyle(SharpitColor.foreground)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

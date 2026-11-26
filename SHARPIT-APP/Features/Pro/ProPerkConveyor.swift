import SwiftUI

/// One thing SharpIt Pro adds, as the paywall says it: a glyph in a pillar's hue and one sentence.
/// The ids are the server's (`pro-perks.ts` in SHARPIT-WEBAPP), whose longer copy Réglages › Pro reads.
/// Each sentence says only what the app does today, with its limits (which watch, which sports):
/// a paywall that sells more than the app offers is refused (App Review 2.3.1, 3.1.2(c)).
nonisolated struct ProPerkLine: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let pillar: CliniquePillar
    let sentence: String

    static let all: [ProPerkLine] = [
        ProPerkLine(id: "coach", symbol: "bubble.left", pillar: .coach, sentence: String(localized: "Un coach qui répond avec ton sommeil et ta charge du moment")),
        ProPerkLine(id: "adaptive-plan", symbol: "calendar", pillar: .recovery, sentence: String(localized: "Séance ratée ou nuit courte : ton plan se réécrit en un geste")),
        ProPerkLine(id: "weekly-review", symbol: "chart.bar", pillar: .sleep, sentence: String(localized: "Le bilan de ta semaine, et la suivante déjà prête")),
        ProPerkLine(id: "session-analysis", symbol: "figure.run", pillar: .recovery, sentence: String(localized: "Chaque séance lue : ce qui a marché, ce qui a coûté")),
        ProPerkLine(id: "journal-coach-read", symbol: "checklist", pillar: .coach, sentence: String(localized: "Le coach repère tes habitudes qui paient et t'en propose une ou deux à tester")),
        ProPerkLine(id: "nutrition-reading", symbol: "flame", pillar: .nutrition, sentence: String(localized: "Le coach compare ton assiette à ta charge, chaque jour")),
        ProPerkLine(id: "biological-age", symbol: "heart", pillar: .sleep, sentence: String(localized: "Ton âge forme, estimé depuis ta VO₂max")),
        ProPerkLine(id: "watch-push", symbol: "applewatch", pillar: .recovery, sentence: String(localized: "Tes séances course, vélo et natation, envoyées sur ta Garmin")),
        ProPerkLine(id: "extra-widgets", symbol: "square.grid.2x2", pillar: .sleep, sentence: String(localized: "Sommeil, poids, volume et régularité sur ton écran d'accueil")),
        ProPerkLine(id: "support", symbol: "hand.raised", pillar: .nutrition, sentence: String(localized: "SharpIt sans publicité ni revente de données, grâce à toi")),
    ]

    /// The paywall's few lines, the plan that repairs itself first; Réglages › Pro lists the rest
    /// from the server.
    static let paywall: [ProPerkLine] = ["adaptive-plan", "coach", "session-analysis", "weekly-review", "watch-push"]
        .compactMap { id in all.first { $0.id == id } }
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

    /// How long the list waits, once the finger has left, before it rises by itself again.
    static let resumeDelay: Double = 2
    /// How long the rise takes to come back to its speed: eased in, never a start.
    static let resumeRamp: Double = 1.6

    /// The offset `elapsed` seconds after the finger left at `fling` points a second: the flick's
    /// travel dies down, the list rests for `delay`, then the rise eases back in.
    static func offset(from anchor: Double, elapsed: Double, fling: Double, delay: Double) -> Double {
        let time = max(elapsed, 0)
        let thrown = min(max(fling, -maxFling), maxFling)
        return anchor + rise(after: time - delay) + thrown * flingDecay * (1 - exp(-time / flingDecay))
    }

    /// How far the list has risen by itself `time` seconds after it set off again: its speed
    /// follows a smoothstep from 0 to `speed` over `resumeRamp`, then holds.
    static func rise(after time: Double) -> Double {
        guard time > 0 else { return 0 }
        guard time < resumeRamp else { return speed * (time - resumeRamp / 2) }
        let progress = time / resumeRamp
        // The integral of 3x² − 2x³, the smoothstep the speed follows.
        return speed * resumeRamp * (pow(progress, 3) - pow(progress, 4) / 2)
    }
}

/// What Pro adds, rising without end under the paywall's title. A finger laid on the list
/// holds it and can take it either way; two seconds after it leaves, the rise eases back in
/// (the athlete's request, 2026-11-24). Under
/// Reduce Motion or at the accessibility text sizes it is the plain list.
struct ProPerkConveyor: View {
    var perks: [ProPerkLine] = ProPerkLine.paywall

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .callout) private var rowHeight: CGFloat = 58
    @State private var anchor: Double = 0
    @State private var anchoredAt = Date.now
    @State private var fling: Double = 0
    /// No wait when the paywall opens; `ConveyorLoop.resumeDelay` once the finger has left.
    @State private var resumeDelay: Double = 0
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
        // Whole points: a fractional row lands on a rounded pixel, and the copy under it would
        // then start a hair off where the wrap expects it.
        let row = rowHeight.rounded()
        let length = Double(row) * Double(perks.count)
        return TimelineView(.animation) { context in
            let offset = ConveyorLoop.wrapped(position(at: context.date), length: length)
            ProPerkStrip(perks: perks, rowHeight: row)
                // Compared, not rebuilt: the clock ticks every frame and the lines never change.
                .equatable()
                // Drawn once into one layer that then slides. Moved as live text, each line was
                // laid out and rasterised again on every frame at a fractional position, which
                // showed as small jumps.
                .drawingGroup()
                .offset(y: -offset)
                .frame(height: row * Self.visibleRows, alignment: .top)
                // The wrap is a jump of one whole list: it must never ride an animation that
                // happens to be running around it (the arrival, a plan being chosen).
                .transaction { $0.animation = nil }
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
        return ConveyorLoop.offset(
            from: anchor, elapsed: date.timeIntervalSince(anchoredAt), fling: fling, delay: resumeDelay
        )
    }

    private var drag: some Gesture {
        // From the touch itself, not from a first movement: a finger laid on the list holds it.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = position(at: .now) }
                dragTravel = value.translation.height
            }
            .onEnded { value in
                anchor = (dragOrigin ?? anchor) - value.translation.height
                anchoredAt = .now
                fling = -value.velocity.height
                resumeDelay = ConveyorLoop.resumeDelay
                dragOrigin = nil
                dragTravel = 0
            }
    }
}

/// The list twice over, so the window is always full whatever part of it shows.
private struct ProPerkStrip: View, Equatable {
    let perks: [ProPerkLine]
    let rowHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { _ in
                ForEach(perks) { perk in
                    ProPerkRow(perk: perk).frame(height: rowHeight)
                }
            }
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

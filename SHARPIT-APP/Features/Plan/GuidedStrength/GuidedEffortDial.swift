import SwiftUI

/// The end of a guided strength session asks its effort on a dial (the athlete's call, 2026-11-28,
/// overriding the root rule against a radial gauge as a hero): a 270° track from 1 to 10, a dot
/// per step, filled from cool to warm up to the knob, the level read big in its centre. The finger
/// turns it anywhere on the dial, a notch per step crossed; VoiceOver adjusts it.
struct GuidedEffortDial: View {
    @Binding var value: Int?
    private let range = 1...10
    /// Where the track starts (bottom left) and how far it runs, clockwise.
    private let start = 135.0
    private let sweep = 270.0

    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 88

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = side * 0.085
            let radius = (side - line) / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                arc(to: 1)
                    .stroke(SharpitColor.tile, style: StrokeStyle(lineWidth: line, lineCap: .round))
                arc(to: fraction)
                    .stroke(
                        AngularGradient(
                            colors: [SharpitColor.zone1, SharpitColor.zone3, SharpitColor.zone5],
                            center: .center,
                            // The gradient is laid in the view, not along the rotated track.
                            startAngle: .degrees(start),
                            endAngle: .degrees(start + sweep)
                        ),
                        style: StrokeStyle(lineWidth: line, lineCap: .round)
                    )
                    .opacity(value == nil ? 0 : 1)

                ForEach(Array(range), id: \.self) { step in
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: line * 0.26, height: line * 0.26)
                        .position(point(for: step, radius: radius, center: center))
                }

                if let value {
                    Circle()
                        .fill(Color.white)
                        .frame(width: line * 1.25, height: line * 1.25)
                        .overlay(Circle().fill(GuidedEffortDial.tone(value)).padding(line * 0.3))
                        .sharpitShadow(.control)
                        .position(point(for: value, radius: radius, center: center))
                }

                Text(value.map(String.init) ?? "—")
                    .font(SharpitTypography.system(size: figureSize, weight: .semibold, relativeTo: .largeTitle, digits: true))
                    .foregroundStyle(value.map(GuidedEffortDial.tone) ?? SharpitColor.slate)
                    .contentTransition(.numericText(value: Double(value ?? 0)))
                    .position(center)

                endLabel("1", at: point(for: 1, radius: radius - line * 1.3, center: center))
                endLabel("10", at: point(for: 10, radius: radius - line * 1.3, center: center))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        SharpitHaptics.prepare()
                        let next = step(at: gesture.location, center: center)
                        guard next != value else { return }
                        value = next
                        SharpitHaptics.play(.notch(major: next == 1 || next == 5 || next == 10))
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(SharpitMotion.selection, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Effort perçu")
        .accessibilityValue(value.map { "\($0) sur 10" } ?? String(localized: "Non renseigné"))
        .accessibilityAdjustableAction { direction in
            let current = value ?? 5
            let next = direction == .increment ? current + 1 : current - 1
            guard range.contains(next) else { return }
            value = next
        }
    }

    private var fraction: Double {
        guard let value else { return 0 }
        return Double(value - range.lowerBound) / Double(range.count - 1)
    }

    /// The track from its start, `share` of the way round, drawn clockwise.
    private func arc(to share: Double) -> some Shape {
        Circle()
            .trim(from: 0, to: sweep / 360 * max(share, 0.0001))
            .rotation(.degrees(start))
    }

    private func angle(for step: Int) -> Double {
        start + sweep * Double(step - range.lowerBound) / Double(range.count - 1)
    }

    private func point(for step: Int, radius: CGFloat, center: CGPoint) -> CGPoint {
        let radians = angle(for: step) * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    /// The step under the finger: its angle along the track, the gap at the bottom read as the
    /// nearer end.
    private func step(at location: CGPoint, center: CGPoint) -> Int {
        let degrees = atan2(location.y - center.y, location.x - center.x) * 180 / .pi
        var along = (degrees - start).truncatingRemainder(dividingBy: 360)
        if along < 0 { along += 360 }
        if along > sweep { along = along > sweep + (360 - sweep) / 2 ? 0 : sweep }
        return range.lowerBound + Int((along / sweep * Double(range.count - 1)).rounded())
    }

    private func endLabel(_ text: String, at point: CGPoint) -> some View {
        Text(text)
            .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
            .foregroundStyle(SharpitColor.foreground)
            .position(point)
            .accessibilityHidden(true)
    }

    /// A level's hue, cool to warm, as the zones run.
    static func tone(_ value: Int) -> Color {
        SharpitZoneTone.color((value - 1) / 2)
    }
}

/// A burst of paper falling over the recap once a session is saved (the athlete's call,
/// 2026-11-28): three seconds, then gone; nothing under Reduce Motion; never in the way of a tap.
struct GuidedConfetti: View {
    private struct Piece {
        let x: Double
        let delay: Double
        let fall: Double
        let drift: Double
        let spin: Double
        let size: CGSize
        let color: Color
    }

    private static let duration = 3.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var pieces: [Piece] = []

    var body: some View {
        Group {
            if !reduceMotion, let startedAt {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince(startedAt)
                    Canvas { canvas, size in
                        for piece in pieces {
                            let local = t - piece.delay
                            guard local > 0 else { continue }
                            let y = -20 + piece.fall * local + 140 * local * local
                            guard y < size.height + 20 else { continue }
                            let x = piece.x * size.width + sin(local * 2.4 + piece.x * 9) * piece.drift
                            let fade = min(1, max(0, (Self.duration - t) / 0.6))
                            var copy = canvas
                            copy.opacity = fade
                            copy.translateBy(x: x, y: y)
                            copy.rotate(by: .degrees(piece.spin * local))
                            let rect = CGRect(origin: CGPoint(x: -piece.size.width / 2, y: -piece.size.height / 2), size: piece.size)
                            copy.fill(Path(rect), with: .color(piece.color))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            guard !reduceMotion, startedAt == nil else { return }
            pieces = Self.burst()
            startedAt = .now
            try? await Task.sleep(for: .seconds(Self.duration))
            pieces = []
        }
    }

    private static func burst() -> [Piece] {
        let colors = [SharpitColor.pillarSleep, SharpitColor.pillarRecovery, SharpitColor.pillarNutrition, SharpitColor.pillarCoach]
        return (0..<70).map { index in
            Piece(
                x: Double.random(in: 0...1),
                delay: Double.random(in: 0...0.5),
                fall: Double.random(in: 60...180),
                drift: Double.random(in: 8...30),
                spin: Double.random(in: -240...240),
                size: CGSize(width: Double.random(in: 7...13), height: Double.random(in: 4...8)),
                color: colors[index % colors.count].opacity(0.75)
            )
        }
    }
}

import SwiftUI

/// Where each of the web's body parts (`COMMON_BODY_PARTS`) sits on a silhouette, and how a tap
/// on it reads as a part and a side. The part's name is the server's own string, so a zone picked
/// here is one the plan can check; a part the server adds later and the map does not know stays
/// a chip under it.
nonisolated enum SensitiveZoneBody {
    enum Face: String, CaseIterable, Hashable, Sendable {
        case front, back
    }

    /// The athlete's own side, as the web stores it.
    enum Side: String, Hashable, Sendable {
        case left = "LEFT"
        case right = "RIGHT"
        case none = "NA"
    }

    /// One place to touch. `x` and `y` are shares of the silhouette as the viewer sees it: on
    /// the front the athlete's left is on the viewer's right, on the back it is on the left.
    struct Spot: Identifiable, Hashable, Sendable {
        let part: String
        let side: Side
        let face: Face
        let x: Double
        let y: Double

        var id: String { "\(face.rawValue)-\(part)-\(side.rawValue)" }
    }

    /// `x` is the spot on the viewer's left; the other side is drawn mirrored.
    private static func pair(_ part: String, _ face: Face, x: Double, y: Double) -> [Spot] {
        let viewerLeft: Side = face == .front ? .right : .left
        let viewerRight: Side = face == .front ? .left : .right
        return [
            Spot(part: part, side: viewerLeft, face: face, x: x, y: y),
            Spot(part: part, side: viewerRight, face: face, x: 1 - x, y: y),
        ]
    }

    private static func single(_ part: String, _ face: Face, y: Double) -> Spot {
        Spot(part: part, side: .none, face: face, x: 0.5, y: y)
    }

    static let spots: [Spot] = {
        var spots: [Spot] = []
        // Face: what is felt from the front.
        spots.append(single("Cou", .front, y: 0.135))
        spots += pair("Épaule", .front, x: 0.29, y: 0.2)
        spots += pair("Pectoraux", .front, x: 0.41, y: 0.23)
        spots += pair("Bras", .front, x: 0.272, y: 0.27)
        spots += pair("Poignet", .front, x: 0.215, y: 0.48)
        spots.append(single("Abdominaux", .front, y: 0.34))
        spots += pair("Hanche", .front, x: 0.36, y: 0.47)
        spots += pair("Psoas", .front, x: 0.44, y: 0.45)
        spots.append(single("Bassin", .front, y: 0.515))
        spots += pair("Adducteurs", .front, x: 0.455, y: 0.575)
        spots += pair("Quadriceps", .front, x: 0.415, y: 0.635)
        // The onboarding's word for the same place: drawn on the zones page, never offered.
        spots += pair("Cuisse", .front, x: 0.415, y: 0.635)
        spots += pair("Genou", .front, x: 0.425, y: 0.725)
        spots += pair("Tibia", .front, x: 0.425, y: 0.81)
        spots += pair("Cheville", .front, x: 0.43, y: 0.905)
        spots += pair("Pied", .front, x: 0.415, y: 0.97)
        // Dos: the back of the body.
        spots.append(single("Cou", .back, y: 0.135))
        spots += pair("Trapèzes", .back, x: 0.41, y: 0.19)
        spots += pair("Épaule", .back, x: 0.29, y: 0.2)
        spots.append(single("Dos", .back, y: 0.26))
        spots += pair("Coude", .back, x: 0.262, y: 0.33)
        spots.append(single("Lombaires", .back, y: 0.4))
        spots += pair("Fessier", .back, x: 0.42, y: 0.49)
        spots += pair("Ischio", .back, x: 0.425, y: 0.62)
        spots += pair("Mollet", .back, x: 0.425, y: 0.8)
        spots += pair("Tendon d'Achille", .back, x: 0.43, y: 0.91)
        return spots
    }()

    /// The spots placed on a figure: a woman's arms hang narrower and closer to the body, so the
    /// spots on them move in.
    static func spots(for figure: SensitiveZoneFigure) -> [Spot] {
        guard figure == .female else { return spots }
        return spots.map { spot in
            guard armParts.contains(spot.part) else { return spot }
            let inward = spot.x < 0.5 ? 0.03 : -0.03
            return Spot(part: spot.part, side: spot.side, face: spot.face, x: spot.x + inward, y: spot.y)
        }
    }

    private static let armParts: Set<String> = ["Épaule", "Bras", "Coude", "Poignet"]

    static let mappedParts: Set<String> = Set(spots.map(\.part))

    static func isOnMap(_ part: String?) -> Bool {
        part.map(mappedParts.contains) ?? false
    }

    static func isPaired(_ part: String) -> Bool {
        spots.contains { $0.part == part && $0.side != .none }
    }

    /// The spots of one face the server offers — a part it does not list is never drawn.
    static func spots(on face: Face, offered: [String], figure: SensitiveZoneFigure = .male) -> [Spot] {
        let offered = Set(offered)
        return spots(for: figure).filter { $0.face == face && offered.contains($0.part) }
    }

    /// The spot a finger at `point` (a share of the silhouette, as `x` and `y`) means: the
    /// nearest one, measured on the figure's 1:2 frame, within `reach` of it.
    static func nearest(to point: CGPoint, in spots: [Spot], reach: Double = 0.09) -> Spot? {
        func distance(_ spot: Spot) -> Double {
            // The figure is twice as tall as it is wide: a share across is half a share down.
            hypot((spot.x - point.x) / 2, spot.y - point.y)
        }
        guard let best = spots.min(by: { distance($0) < distance($1) }), distance(best) <= reach else { return nil }
        return best
    }

    /// The face a part opens on: the back for the back of the body, else the front.
    static func face(for part: String?) -> Face {
        guard let part else { return .front }
        let faces = Set(spots.filter { $0.part == part }.map(\.face))
        return faces == [.back] ? .back : .front
    }

    /// The sides a stored side covers.
    private static func sides(_ side: String) -> Set<Side> {
        switch side {
        case "LEFT": [.left]
        case "RIGHT": [.right]
        case "BILATERAL": [.left, .right]
        default: []
        }
    }

    /// Whether a spot is part of the zone as it stands.
    static func isSelected(_ spot: Spot, part: String?, side: String) -> Bool {
        guard spot.part == part else { return false }
        if spot.side == .none { return true }
        return sides(side).contains(spot.side)
    }

    /// A tap on a spot: another part takes its place; on the same paired part it adds or removes
    /// that side (both sides read « Les deux »); the last side, or a single part, tapped again
    /// clears the choice.
    static func select(_ spot: Spot, part: String?, side: String) -> (part: String?, side: String) {
        guard spot.part == part else { return (spot.part, spot.side.rawValue) }
        guard spot.side != .none else { return (nil, Side.none.rawValue) }
        var chosen = sides(side)
        if chosen.contains(spot.side) { chosen.remove(spot.side) } else { chosen.insert(spot.side) }
        switch chosen {
        case [.left, .right]: return (part, "BILATERAL")
        case [.left]: return (part, Side.left.rawValue)
        case [.right]: return (part, Side.right.rawValue)
        default: return (nil, Side.none.rawValue)
        }
    }

    /// The parts French makes feminine, so the right one reads « Épaule droite ».
    private static let feminineParts: Set<String> = ["Cheville", "Cuisse", "Hanche", "Épaule"]

    /// « Genou gauche », « Épaule droite », « Genou · des deux côtés », « Lombaires ».
    static func caption(part: String?, side: String) -> String? {
        guard let part else { return nil }
        switch side {
        case "LEFT": return String(localized: "\(part) gauche")
        case "RIGHT": return feminineParts.contains(part) ? String(localized: "\(part) droite") : String(localized: "\(part) droit")
        case "BILATERAL": return String(localized: "\(part) · des deux côtés")
        default: return part
        }
    }

    static func label(_ spot: Spot) -> String {
        switch spot.side {
        case .left: String(localized: "\(spot.part), côté gauche")
        case .right: String(localized: "\(spot.part), côté droit")
        case .none: spot.part
        }
    }
}

/// A standing figure, one fill, drawn as the athlete declared themself: a man's broader shoulders
/// and straighter waist, a woman's narrower shoulders and waist and wider hips. Anything else, or
/// nothing declared, draws the man's figure.
nonisolated enum SensitiveZoneFigure: Sendable {
    case male, female

    init(sex: AthleteSex?) {
        self = sex == .female ? .female : .male
    }

    /// The right half of the outline as the viewer sees it, from the crown down the arm and back up
    /// its inside, then the flank and the leg and back up its inside to the crotch — in shares of
    /// the figure's width (`x`, 0.5 the centre line) and height (`y`). The left half is its mirror.
    var halfOutline: [CGPoint] {
        let points: [(Double, Double)] = switch self {
        case .male: [
            (0.5, 0.0), (0.56, 0.008), (0.59, 0.035), (0.595, 0.065), (0.585, 0.095), (0.56, 0.12),
            (0.545, 0.132), (0.54, 0.148), (0.56, 0.165), (0.62, 0.176), (0.70, 0.186), (0.745, 0.205),
            (0.765, 0.24), (0.775, 0.29), (0.78, 0.33), (0.79, 0.38), (0.80, 0.43), (0.805, 0.47),
            (0.815, 0.50), (0.815, 0.535), (0.80, 0.56), (0.78, 0.555), (0.77, 0.53), (0.765, 0.48),
            (0.75, 0.43), (0.735, 0.37), (0.725, 0.33), (0.71, 0.29), (0.69, 0.245), (0.68, 0.27),
            (0.668, 0.32), (0.652, 0.37), (0.655, 0.41), (0.664, 0.45), (0.67, 0.49), (0.665, 0.53),
            (0.655, 0.58), (0.64, 0.64), (0.625, 0.70), (0.62, 0.73), (0.625, 0.77), (0.62, 0.82),
            (0.60, 0.88), (0.59, 0.92), (0.60, 0.95), (0.62, 0.975), (0.615, 0.99), (0.56, 0.995),
            (0.545, 0.985), (0.545, 0.95), (0.55, 0.90), (0.545, 0.84), (0.545, 0.79), (0.54, 0.74),
            (0.535, 0.68), (0.52, 0.60), (0.51, 0.548), (0.5, 0.54),
        ]
        case .female: [
            (0.5, 0.0), (0.555, 0.008), (0.583, 0.035), (0.588, 0.065), (0.578, 0.095), (0.555, 0.12),
            (0.54, 0.132), (0.535, 0.15), (0.555, 0.166), (0.61, 0.177), (0.68, 0.19), (0.715, 0.21),
            (0.735, 0.245), (0.745, 0.29), (0.75, 0.33), (0.76, 0.38), (0.77, 0.43), (0.775, 0.47),
            (0.785, 0.50), (0.785, 0.53), (0.77, 0.555), (0.75, 0.55), (0.74, 0.525), (0.735, 0.48),
            (0.72, 0.43), (0.705, 0.37), (0.695, 0.33), (0.68, 0.29), (0.665, 0.25), (0.668, 0.27),
            (0.66, 0.30), (0.635, 0.34), (0.625, 0.37), (0.64, 0.41), (0.665, 0.45), (0.685, 0.49),
            (0.685, 0.53), (0.67, 0.58), (0.65, 0.64), (0.625, 0.70), (0.615, 0.73), (0.62, 0.77),
            (0.612, 0.82), (0.595, 0.88), (0.585, 0.92), (0.595, 0.95), (0.612, 0.975), (0.605, 0.99),
            (0.555, 0.995), (0.542, 0.985), (0.542, 0.95), (0.547, 0.90), (0.542, 0.84), (0.54, 0.79),
            (0.535, 0.74), (0.528, 0.68), (0.515, 0.60), (0.505, 0.55), (0.5, 0.54),
        ]
        }
        return points.map { CGPoint(x: $0.0, y: $0.1) }
    }

    /// The whole outline, closed: the right half, then its mirror from the crotch back to the crown.
    var outline: [CGPoint] {
        let right = halfOutline
        return right + right.dropFirst().dropLast().reversed().map { CGPoint(x: 1 - $0.x, y: $0.y) }
    }
}

/// The figure's outline smoothed through its points (Catmull-Rom as cubic Béziers), on the same
/// unit square as the spots.
nonisolated struct SensitiveZoneSilhouette: Shape {
    var figure: SensitiveZoneFigure = .male

    func path(in rect: CGRect) -> Path {
        let points = figure.outline.map {
            CGPoint(x: rect.minX + rect.width * $0.x, y: rect.minY + rect.height * $0.y)
        }
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in points.indices {
            let p0 = points[(index - 1 + points.count) % points.count]
            let p1 = points[index]
            let p2 = points[(index + 1) % points.count]
            let p3 = points[(index + 2) % points.count]
            path.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        path.closeSubpath()
        return path
    }
}

/// The silhouette with its spots. In the form every offered spot can be touched and the chosen
/// ones fill lime; on the zones page only the open zones show, in what they do to the plan.
struct SensitiveZoneBodyMap: View {
    let face: SensitiveZoneBody.Face
    let spots: [SensitiveZoneBody.Spot]
    /// The tint of a spot that is part of a zone; nil leaves it an empty ring.
    let tint: (SensitiveZoneBody.Spot) -> Color?
    /// Nil draws marks only.
    var onTap: ((SensitiveZoneBody.Spot) -> Void)?
    var height: CGFloat = 400
    var figure: SensitiveZoneFigure = .male

    private var width: CGFloat { height / 2 }
    /// A dot's own target; a tap off every dot still reaches the nearest one.
    private var target: CGFloat { max(22, height * 0.06) }
    private var dot: CGFloat { max(10, height * 0.034) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SensitiveZoneSilhouette(figure: figure)
                .fill(SharpitColor.mutedForeground.opacity(0.14))
                .frame(width: width, height: height)
                .contentShape(.rect)
                // Anywhere on the figure, not only on a dot: the nearest part is the one meant.
                .onTapGesture(coordinateSpace: .local) { location in
                    guard let onTap else { return }
                    let point = CGPoint(x: location.x / width, y: location.y / height)
                    if let spot = SensitiveZoneBody.nearest(to: point, in: spots) { onTap(spot) }
                }
                .accessibilityHidden(true)
            ForEach(spots) { spot in
                spotView(spot)
                    .position(x: width * spot.x, y: height * spot.y)
            }
        }
        .frame(width: width, height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(face == .front ? String(localized: "Silhouette de face") : String(localized: "Silhouette de dos"))
    }

    @ViewBuilder
    private func spotView(_ spot: SensitiveZoneBody.Spot) -> some View {
        let fill = tint(spot)
        let mark = Circle()
            .fill(fill ?? SharpitColor.card)
            .overlay(
                Circle().strokeBorder(fill == nil ? SharpitColor.mutedForeground.opacity(0.7) : SharpitColor.foreground, lineWidth: fill == nil ? 1.5 : 2)
            )
            .frame(width: fill == nil ? dot : dot * 1.35, height: fill == nil ? dot : dot * 1.35)
            .frame(width: target, height: target)
            .contentShape(Circle())
        if let onTap {
            Button { onTap(spot) } label: { mark }
                .buttonStyle(.plain)
                .accessibilityLabel(SensitiveZoneBody.label(spot))
                .accessibilityAddTraits(fill == nil ? [] : .isSelected)
        } else {
            mark.accessibilityLabel(SensitiveZoneBody.label(spot))
        }
    }
}

/// « Où ? » in the zone form: the body, face or back, the zone touched on it — its side read
/// from where the finger landed — and the zone named under it.
struct SensitiveZoneBodyPicker: View {
    let offered: [String]
    var figure: SensitiveZoneFigure = .male
    @Binding var part: String?
    @Binding var side: String
    /// Called on every tap, so the form leaves its own free-text part.
    var onPick: () -> Void = {}

    @State private var face: SensitiveZoneBody.Face

    init(
        offered: [String],
        figure: SensitiveZoneFigure = .male,
        part: Binding<String?>,
        side: Binding<String>,
        onPick: @escaping () -> Void = {}
    ) {
        self.offered = offered
        self.figure = figure
        _part = part
        _side = side
        self.onPick = onPick
        _face = State(initialValue: SensitiveZoneBody.face(for: part.wrappedValue))
    }

    var body: some View {
        VStack(spacing: SharpitSpacing.sm) {
            SharpitSegmentedControl(
                selection: $face,
                options: [
                    .init(value: .front, label: String(localized: "Face")),
                    .init(value: .back, label: String(localized: "Dos")),
                ]
            )
            SensitiveZoneBodyMap(
                face: face,
                spots: SensitiveZoneBody.spots(on: face, offered: offered, figure: figure),
                tint: { spot in
                    SensitiveZoneBody.isSelected(spot, part: part, side: side) ? SharpitColor.highlight : nil
                },
                onTap: { spot in
                    SharpitMotion.run(SharpitMotion.selection) {
                        let next = SensitiveZoneBody.select(spot, part: part, side: side)
                        part = next.part
                        side = next.side
                    }
                    onPick()
                },
                height: 460,
                figure: figure
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, SharpitSpacing.xs)

            Text(SensitiveZoneBody.isOnMap(part)
                 ? SensitiveZoneBody.caption(part: part, side: side) ?? ""
                 : String(localized: "Touche la zone sur la silhouette."))
                .font(SensitiveZoneBody.isOnMap(part) ? SharpitTypography.bodyEmphasis : SharpitTypography.meta)
                .foregroundStyle(SensitiveZoneBody.isOnMap(part) ? SharpitColor.foreground : SharpitColor.mutedForeground)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// The zones page's figure: face and back side by side, a mark on each open zone in what it
/// does to the plan. Only zones on a part the map knows are drawn; the list below names them all.
struct SensitiveZonesBodyOverview: View {
    let zones: [V1SensitiveZone]
    var figure: SensitiveZoneFigure = .male

    private func tint(_ spot: SensitiveZoneBody.Spot) -> Color? {
        zones.first { SensitiveZoneBody.isSelected(spot, part: $0.bodyPart, side: $0.side) }?.strategy.tint
    }

    private func spots(_ face: SensitiveZoneBody.Face) -> [SensitiveZoneBody.Spot] {
        SensitiveZoneBody.spots(for: figure).filter { $0.face == face && tint($0) != nil }
    }

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.lg) {
            ForEach(SensitiveZoneBody.Face.allCases, id: \.self) { face in
                VStack(spacing: SharpitSpacing.xs) {
                    SensitiveZoneBodyMap(face: face, spots: spots(face), tint: tint, height: 220, figure: figure)
                    Text(face == .front ? String(localized: "Face") : String(localized: "Dos"))
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

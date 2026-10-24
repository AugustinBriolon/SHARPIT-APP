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
        spots += pair("Épaule", .front, x: 0.3, y: 0.175)
        spots += pair("Pectoraux", .front, x: 0.41, y: 0.23)
        spots += pair("Bras", .front, x: 0.275, y: 0.25)
        spots += pair("Poignet", .front, x: 0.24, y: 0.5)
        spots.append(single("Abdominaux", .front, y: 0.34))
        spots += pair("Hanche", .front, x: 0.345, y: 0.465)
        spots += pair("Psoas", .front, x: 0.44, y: 0.45)
        spots.append(single("Bassin", .front, y: 0.515))
        spots += pair("Adducteurs", .front, x: 0.455, y: 0.575)
        spots += pair("Quadriceps", .front, x: 0.4, y: 0.635)
        // The onboarding's word for the same place: drawn on the zones page, never offered.
        spots += pair("Cuisse", .front, x: 0.4, y: 0.635)
        spots += pair("Genou", .front, x: 0.425, y: 0.725)
        spots += pair("Tibia", .front, x: 0.425, y: 0.81)
        spots += pair("Cheville", .front, x: 0.425, y: 0.895)
        spots += pair("Pied", .front, x: 0.415, y: 0.965)
        // Dos: the back of the body.
        spots.append(single("Cou", .back, y: 0.135))
        spots += pair("Trapèzes", .back, x: 0.4, y: 0.165)
        spots += pair("Épaule", .back, x: 0.3, y: 0.19)
        spots.append(single("Dos", .back, y: 0.26))
        spots += pair("Coude", .back, x: 0.255, y: 0.33)
        spots.append(single("Lombaires", .back, y: 0.4))
        spots += pair("Fessier", .back, x: 0.42, y: 0.49)
        spots += pair("Ischio", .back, x: 0.425, y: 0.62)
        spots += pair("Mollet", .back, x: 0.425, y: 0.8)
        spots += pair("Tendon d'Achille", .back, x: 0.425, y: 0.905)
        return spots
    }()

    static let mappedParts: Set<String> = Set(spots.map(\.part))

    static func isOnMap(_ part: String?) -> Bool {
        part.map(mappedParts.contains) ?? false
    }

    static func isPaired(_ part: String) -> Bool {
        spots.contains { $0.part == part && $0.side != .none }
    }

    /// The spots of one face the server offers — a part it does not list is never drawn.
    static func spots(on face: Face, offered: [String]) -> [Spot] {
        let offered = Set(offered)
        return spots.filter { $0.face == face && offered.contains($0.part) }
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

/// A plain standing figure, one fill: head, neck, trunk, arms and legs as rounded shapes laid out
/// on the same unit square as the spots.
nonisolated struct SensitiveZoneSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func box(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> CGRect {
            CGRect(
                x: rect.minX + rect.width * x0,
                y: rect.minY + rect.height * y0,
                width: rect.width * (x1 - x0),
                height: rect.height * (y1 - y0)
            )
        }
        func rounded(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, radius: Double) {
            let frame = box(x0, y0, x1, y1)
            let corner = min(frame.width, frame.height) * radius
            path.addRoundedRect(in: frame, cornerSize: CGSize(width: corner, height: corner), style: .continuous)
        }
        func limb(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
            // Both sides, the second mirrored.
            rounded(x0, y0, x1, y1, radius: 0.5)
            rounded(1 - x1, y0, 1 - x0, y1, radius: 0.5)
        }

        path.addEllipse(in: box(0.415, 0.0, 0.585, 0.105))
        rounded(0.455, 0.09, 0.545, 0.16, radius: 0.3)
        // Trunk and pelvis.
        rounded(0.31, 0.145, 0.69, 0.45, radius: 0.28)
        rounded(0.34, 0.41, 0.66, 0.54, radius: 0.35)
        // Arms: upper, fore, hand.
        limb(0.235, 0.155, 0.315, 0.34)
        limb(0.21, 0.32, 0.285, 0.5)
        limb(0.205, 0.49, 0.275, 0.55)
        // Legs: thigh, shin, foot.
        limb(0.355, 0.5, 0.495, 0.74)
        limb(0.37, 0.72, 0.48, 0.93)
        limb(0.355, 0.92, 0.475, 0.985)
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

    private var width: CGFloat { height / 2 }
    /// A dot's own target; a tap off every dot still reaches the nearest one.
    private var target: CGFloat { max(22, height * 0.06) }
    private var dot: CGFloat { max(10, height * 0.034) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SensitiveZoneSilhouette()
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
    @Binding var part: String?
    @Binding var side: String
    /// Called on every tap, so the form leaves its own free-text part.
    var onPick: () -> Void = {}

    @State private var face: SensitiveZoneBody.Face

    init(offered: [String], part: Binding<String?>, side: Binding<String>, onPick: @escaping () -> Void = {}) {
        self.offered = offered
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
                spots: SensitiveZoneBody.spots(on: face, offered: offered),
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
                height: 460
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

    private func tint(_ spot: SensitiveZoneBody.Spot) -> Color? {
        zones.first { SensitiveZoneBody.isSelected(spot, part: $0.bodyPart, side: $0.side) }?.strategy.tint
    }

    private func spots(_ face: SensitiveZoneBody.Face) -> [SensitiveZoneBody.Spot] {
        SensitiveZoneBody.spots.filter { $0.face == face && tint($0) != nil }
    }

    var body: some View {
        HStack(alignment: .top, spacing: SharpitSpacing.lg) {
            ForEach(SensitiveZoneBody.Face.allCases, id: \.self) { face in
                VStack(spacing: SharpitSpacing.xs) {
                    SensitiveZoneBodyMap(face: face, spots: spots(face), tint: tint, height: 220)
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

import SwiftUI

// The Clinique primitives (SHARPIT-WEBAPP ADR-130, ADR-131; `docs/adr/0035`).
//
// They sit beside the Ink & Lime components and share none of their tokens, so a screen moves
// to them whole. Ink runs the interface; a hue appears only on a ring, a glyph or a chart mark.

/// What a value's reading is, always shown with a word beside it.
nonisolated enum CliniqueStatus: CaseIterable, Sendable {
    case good
    case watch
    case alert
    case unknown
    case protect
    case pro

    var fill: Color {
        switch self {
        case .good: SharpitColor.statusGood
        case .watch: SharpitColor.statusWatch
        case .alert: SharpitColor.statusAlert
        case .unknown: SharpitColor.statusUnknown
        case .protect: SharpitColor.statusProtect
        case .pro: SharpitColor.statusPro
        }
    }

    var border: Color {
        switch self {
        case .good: SharpitColor.statusGoodBorder
        case .watch: SharpitColor.statusWatchBorder
        case .alert: SharpitColor.statusAlertBorder
        case .unknown: SharpitColor.statusUnknownBorder
        case .protect: SharpitColor.statusProtectBorder
        case .pro: SharpitColor.statusProBorder
        }
    }

    var foreground: Color {
        switch self {
        case .good: SharpitColor.statusGoodForeground
        case .watch: SharpitColor.statusWatchForeground
        case .alert: SharpitColor.statusAlertForeground
        case .unknown: SharpitColor.statusUnknownForeground
        case .protect: SharpitColor.statusProtectForeground
        case .pro: SharpitColor.statusProForeground
        }
    }

    var mark: Color {
        switch self {
        case .good: SharpitColor.statusGoodMark
        case .watch: SharpitColor.statusWatchMark
        case .alert: SharpitColor.statusAlertMark
        case .unknown: SharpitColor.statusUnknownMark
        case .protect: SharpitColor.statusProtectMark
        case .pro: SharpitColor.statusProMark
        }
    }
}

/// A status word in its fill, border and ink, with the dot that repeats the reading for the eye.
struct CliniqueStatusPill: View {
    let text: String
    let status: CliniqueStatus

    init(_ text: String, status: CliniqueStatus) {
        self.text = text
        self.status = status
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.mark)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(text)
                .font(SharpitTypography.system(size: 13, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(status.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(status.fill, in: shape)
        .overlay(shape.strokeBorder(status.border, lineWidth: 1))
        .fixedSize()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SharpitTokens.pillShapeRadius, style: .continuous)
    }
}

/// The four things the app scores, each with the one hue and glyph that name it.
nonisolated enum CliniquePillar: CaseIterable, Sendable {
    case sleep
    case recovery
    case nutrition
    case coach

    var color: Color {
        switch self {
        case .sleep: SharpitColor.pillarSleep
        case .recovery: SharpitColor.pillarRecovery
        case .nutrition: SharpitColor.pillarNutrition
        case .coach: SharpitColor.pillarCoach
        }
    }

    var symbol: String {
        switch self {
        case .sleep: "moon.fill"
        case .recovery: "bolt.fill"
        case .nutrition: "flame.fill"
        case .coach: "checkmark"
        }
    }
}

enum CliniqueRingMath {
    /// The arc to draw: nothing while the value is unknown, otherwise the fraction held to 0…1.
    static func trim(for fraction: Double?) -> Double {
        guard let fraction else { return 0 }
        return SharpitProgressMath.clamped(fraction)
    }
}

/// A thin ring with its pillar's glyph inside. A `nil` fraction is « no data yet »: the track
/// and a greyed glyph, so an empty score never reads as a zero.
struct CliniqueRing: View {
    let pillar: CliniquePillar
    let fraction: Double?
    var symbol: String? = nil
    var size: CGFloat = 52

    @State private var shown: Double

    private static let lineWidth: CGFloat = 3

    /// `animated: false` draws the arc already filled, for a page shown again or beside a swipe.
    init(pillar: CliniquePillar, fraction: Double?, symbol: String? = nil, size: CGFloat = 52, animated: Bool = true) {
        self.pillar = pillar
        self.fraction = fraction
        self.symbol = symbol
        self.size = size
        _shown = State(initialValue: animated ? 0 : CliniqueRingMath.trim(for: fraction))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(SharpitColor.divider, lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(pillar.color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol ?? pillar.symbol)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(fraction == nil ? SharpitColor.slate.opacity(0.45) : pillar.color)
        }
        .padding(Self.lineWidth / 2)
        .frame(width: size, height: size)
        .onAppear { fill(to: fraction) }
        .onChange(of: fraction) { _, new in fill(to: new) }
        .accessibilityHidden(true)
    }

    private func fill(to fraction: Double?) {
        SharpitMotion.run(SharpitMotion.gaugeFill) {
            shown = CliniqueRingMath.trim(for: fraction)
        }
    }
}

/// A sport's glyph in a round neutral tile: a session is told by its glyph, never by a colour.
struct CliniqueSportTile: View {
    let symbol: String
    var size: CGFloat = SharpitTokens.tileSize
    var isDimmed = false

    var body: some View {
        Image(sharpitSymbol: symbol)
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(isDimmed ? SharpitColor.slate : SharpitColor.foreground)
            .frame(width: size, height: size)
            .background(SharpitColor.tile, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Capsule buttons: ink for the one main action, an outline for a second one, plain text for a way out.
struct CliniqueButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case outline
        case plain
    }

    var kind: Kind = .primary
    /// 52 pt for the main action of a flow; 44 pt otherwise.
    var isLarge = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SharpitTypography.system(size: isLarge ? 16 : 15, weight: .semibold, relativeTo: .body))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, kind == .plain ? 0 : (kind == .primary ? 22 : 16))
            .frame(minHeight: isLarge ? SharpitTokens.controlHeight : SharpitSpacing.minimumTouchTarget)
            .background(kind == .primary ? SharpitColor.primary : .clear, in: Capsule())
            .overlay {
                if kind == .outline {
                    Capsule().strokeBorder(SharpitColor.outline, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }

    private var foreground: Color {
        switch kind {
        case .primary: SharpitColor.primaryForeground
        case .outline: SharpitColor.foreground
        case .plain: SharpitColor.slate
        }
    }
}

extension ButtonStyle where Self == CliniqueButtonStyle {
    static var cliniquePrimary: CliniqueButtonStyle { CliniqueButtonStyle(kind: .primary) }
    static var cliniquePrimaryLarge: CliniqueButtonStyle { CliniqueButtonStyle(kind: .primary, isLarge: true) }
    static var cliniqueOutline: CliniqueButtonStyle { CliniqueButtonStyle(kind: .outline) }
    static var cliniquePlain: CliniqueButtonStyle { CliniqueButtonStyle(kind: .plain) }
}

/// The tint a sheet fades from at its top: the screen's status, or its pillar.
nonisolated enum CliniqueWash: CaseIterable, Sendable {
    case good
    case watch
    case alert
    case neutral
    case sleep
    case coach

    var color: Color {
        switch self {
        case .good: SharpitColor.washGood
        case .watch: SharpitColor.washWatch
        case .alert: SharpitColor.washAlert
        case .neutral: SharpitColor.washNeutral
        case .sleep: SharpitColor.washSleep
        case .coach: SharpitColor.washCoach
        }
    }
}

/// The 1 pt line between rows, and under a table header.
struct CliniqueDivider: View {
    var body: some View {
        Rectangle()
            .fill(SharpitColor.divider)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

extension View {
    /// A bordered card: a hairline instead of a shadow, so it reads as part of the sheet.
    func cliniqueCard(border: Color = SharpitColor.divider) -> some View {
        let shape = RoundedRectangle(cornerRadius: SharpitTokens.cardShapeRadius, style: .continuous)
        return padding(SharpitSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(shape.strokeBorder(border, lineWidth: 1))
    }

    /// The sheet surface with its one wash at the top; everything below is the card colour.
    func cliniqueSheet(wash: CliniqueWash, height: CGFloat = 150) -> some View {
        background(alignment: .top) {
            ZStack(alignment: .top) {
                SharpitColor.card
                LinearGradient(colors: [wash.color, SharpitColor.card], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            }
            .ignoresSafeArea()
        }
    }
}

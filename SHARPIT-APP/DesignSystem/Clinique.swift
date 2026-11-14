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

/// One score of a row of rings: the ring, its name, then the figure over its scale. Without a
/// value it reads « Pas encore » under an empty ring.
struct CliniqueScoreColumn: View {
    let pillar: CliniquePillar
    let fraction: Double?
    var symbol: String? = nil
    let title: String
    let value: String?
    var scale: String? = nil
    /// Said after the figure, in slate: « 56 ml/kg ».
    var unit: String? = nil
    /// A line under the figure that says how to read it: « 3 ans de moins », « Excellent ».
    var note: String? = nil
    var isPulsing = false
    var animated = true

    var body: some View {
        VStack(spacing: 6) {
            CliniqueRing(pillar: pillar, fraction: fraction, symbol: symbol, animated: animated)
                .padding(.bottom, 2)
            Text(title)
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let value {
                (Text(value)
                    .font(SharpitTypography.system(size: 17, weight: .semibold, relativeTo: .body, digits: true))
                    .foregroundStyle(SharpitColor.foreground)
                    + Text(scale.map { " / \($0)" } ?? unit.map { " \($0)" } ?? "").font(SharpitTypography.meta).foregroundStyle(SharpitColor.slate))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .opacity(isPulsing ? 0.55 : 1)
            } else {
                Text("Pas encore")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.slate)
            }
            if let note, value != nil {
                Text(note)
                    .font(SharpitTypography.system(size: 12, weight: .regular, relativeTo: .caption2, digits: true))
                    .foregroundStyle(SharpitColor.slate)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, SharpitSpacing.xxs)
        .frame(maxWidth: .infinity)
    }
}

/// A row of scores between two hairlines, its columns split by a hairline too.
struct CliniqueScoreStrip<Columns: View>: View {
    @ViewBuilder var columns: Columns

    var body: some View {
        VStack(spacing: 0) {
            CliniqueDivider()
            HStack(alignment: .top, spacing: 0) {
                Group(subviews: columns) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { index, column in
                        if index > 0 {
                            Rectangle().fill(SharpitColor.divider).frame(width: 1).accessibilityHidden(true)
                        }
                        column
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 18)
            CliniqueDivider()
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
            // The press is felt, as `SharpitPressableStyle` gives every tile: a hair smaller, at once.
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(SharpitMotion.selection, value: configuration.isPressed)
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

/// A tab's name and glyph, drawn in outline: the bar fills its symbols by default, and the
/// Clinique tab bar keeps them as lines, the selected one told by its pill.
struct SharpitTabLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(uiImage: Self.outline(systemImage))
        }
    }

    /// The symbol drawn into a plain template image: the tab bar swaps a symbol for its filled
    /// variant, whatever the environment says, and cannot do so with a bitmap.
    private static func outline(_ name: String) -> UIImage {
        let configuration = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return UIImage() }
        return UIGraphicsImageRenderer(size: symbol.size)
            .image { _ in symbol.draw(at: .zero) }
            .withRenderingMode(.alwaysTemplate)
    }
}

/// What shows behind a sheet's rounded top: ink on light, the deep canvas on dark. Résumé's
/// date sits on it, in the dark colour scheme.
struct CliniqueBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The mock-up's backdrop: ink with a breath of green, never a brand hue.
        colorScheme == .dark ? SharpitColor.background : Color(red: 15 / 255, green: 31 / 255, blue: 28 / 255)
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

    /// A sheet that rises over a backdrop band: its top corners rounded, its wash under them.
    func cliniqueRisingSheet(wash: CliniqueWash, height: CGFloat = 150) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: SharpitTokens.sheetShapeRadius, topTrailingRadius: SharpitTokens.sheetShapeRadius,
            style: .continuous
        )
        return background(alignment: .top) {
            ZStack(alignment: .top) {
                SharpitColor.card
                LinearGradient(colors: [wash.color, SharpitColor.card], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            }
            .clipShape(shape)
        }
    }

    /// The page behind a rising sheet: the backdrop at the top, where the date sits and where a
    /// pull shows, and the sheet's own colour below it, so a short day never ends on the backdrop.
    func cliniqueBackdropPage() -> some View {
        background {
            VStack(spacing: 0) {
                CliniqueBackdrop().frame(height: 360)
                SharpitColor.card
            }
            .ignoresSafeArea()
        }
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

/// A drill-down is read whole: the tab bar leaves, and the tab it came from is one tap away.
struct CliniqueReturnButton: ViewModifier {
    let tab: ShellTab
    let symbol: String
    let label: String
    @Environment(\.dismiss) private var dismiss
    @Environment(ShellRouter.self) private var router: ShellRouter?

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .overlay(alignment: .bottomLeading) {
                Button {
                    dismiss()
                    router?.select(tab)
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(SharpitColor.foreground)
                        .frame(width: 54, height: 54)
                        .sharpitGlassCircle()
                }
                .buttonStyle(.sharpitPressable)
                .accessibilityLabel(label)
                .padding(.leading, 16)
                .padding(.bottom, 4)
            }
    }
}

extension View {
    func cliniqueReturnButton(to tab: ShellTab = .today, symbol: String = "house", label: String = String(localized: "Résumé")) -> some View {
        modifier(CliniqueReturnButton(tab: tab, symbol: symbol, label: label))
    }
}

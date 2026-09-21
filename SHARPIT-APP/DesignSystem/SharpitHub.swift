import SwiftUI

/// A titled group of destinations, as the web's Réglages hub draws them.
///
/// The rows share one surface rather than each taking their own: a list of eight separate
/// panels reads as eight unrelated things, where the web's grouped plates read as one
/// subject with several ways in. The title sits outside the surface, so the group names
/// itself without spending a row.
struct SharpitHubGroup<Content: View>: View {
    let title: String
    @ViewBuilder let rows: Content

    init(_ title: String, @ViewBuilder rows: () -> Content) {
        self.title = title
        self.rows = rows()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(title)
            // Read as subviews so the group draws the separators itself: a caller
            // interleaving them by hand would eventually leave one after the last row.
            VStack(spacing: 0) {
                Group(subviews: rows) { subviews in
                    ForEach(subviews.indices, id: \.self) { index in
                        if index > subviews.startIndex {
                            SharpitHubDivider()
                        }
                        subviews[index]
                    }
                }
            }
            .sharpitSurface(.panel)
        }
    }
}

/// One destination inside a `SharpitHubGroup`.
///
/// `SharpitHubRow` draws the row; what it does is the caller's business. Wrapped in a
/// `NavigationLink` or a `Button` it is an affordance and takes a chevron; standing alone
/// it carries whatever control it was given — a toggle, a value — and takes none. A row
/// that leads nowhere yet says so instead of failing quietly when tapped.
struct SharpitHubRow<Accessory: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    var tone: Color = SharpitColor.primary
    /// Drawn muted, with no accessory: named so the athlete knows it is coming, not
    /// hidden until it ships.
    var comingSoon: Bool = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: SharpitSpacing.sm) {
            Image(systemName: symbol)
                .font(SharpitTypography.bodyEmphasis)
                .foregroundStyle(comingSoon ? SharpitColor.mutedForeground : tone)
                .frame(width: SharpitHubRowMetrics.iconSize, height: SharpitHubRowMetrics.iconSize)
                .background((comingSoon ? SharpitColor.mutedForeground : tone).opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(comingSoon ? SharpitColor.mutedForeground : SharpitColor.foreground)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: SharpitSpacing.xs)
            if comingSoon {
                Text("Bientôt")
                    .font(SharpitTypography.label)
                    .tracking(SharpitTypography.labelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(SharpitColor.mutedForeground)
            } else {
                accessory
            }
        }
        .padding(SharpitSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

extension SharpitHubRow where Accessory == SharpitHubChevron {
    /// The common case: a row that opens something.
    init(
        symbol: String,
        title: String,
        detail: String? = nil,
        tone: Color = SharpitColor.primary,
        comingSoon: Bool = false
    ) {
        self.init(
            symbol: symbol,
            title: title,
            detail: detail,
            tone: tone,
            comingSoon: comingSoon,
            accessory: { SharpitHubChevron() }
        )
    }
}

/// The mark of a row that opens something (ADR 0004).
struct SharpitHubChevron: View {
    /// An outward arrow for a destination that leaves the app, a chevron for one inside it.
    var leavesApp: Bool = false

    var body: some View {
        Image(systemName: leavesApp ? "arrow.up.right" : "chevron.right")
            .font(SharpitTypography.label)
            .foregroundStyle(SharpitColor.mutedForeground)
            .accessibilityHidden(true)
    }
}

/// Separates two rows of the same group. A group draws it between rows and never after the
/// last one, so the surface ends on the row rather than on a line.
///
/// It starts where the row's text starts, not at the edge: a line under the icon would cut
/// the column of icons in two.
struct SharpitHubDivider: View {
    var body: some View {
        Rectangle()
            .fill(SharpitColor.analysisGrid)
            .frame(height: SharpitStroke.hairline)
            .padding(.leading, SharpitHubRowMetrics.textInset)
    }
}

/// Shared between the row and the divider that has to line up with it.
///
/// Main-actor isolated like the spacing scale it is built from: these are layout numbers a
/// view reads, not a value type crossing an actor boundary.
enum SharpitHubRowMetrics {
    static let iconSize: CGFloat = 32

    /// Where a row's text begins, measured from the surface edge: the row's own padding,
    /// then the icon, then the gap after it. The divider starts here so the column of icons
    /// stays whole.
    static let textInset: CGFloat = SharpitSpacing.md + iconSize + SharpitSpacing.sm
}

import SwiftUI

/// The system's inset-grouped `List`, dressed in SHARPIT's canvas and typeface
/// (`docs/adr/0008`).
///
/// Structure, row metrics, separators and Dynamic Type stay the system's; the brand lives in
/// the palette and the words. A settings-like screen is this list and nothing custom on top.
extension View {
    /// Apply to the `List`. The default font and ink are set here so every row label — a
    /// `Label`, a `Toggle`, a `LabeledContent` — reads in the brand body face and text colour
    /// without each one asking; left alone they fall back to SF Pro in system black.
    func sharpitGroupedList() -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(SharpitElevatedColor.groupedCanvas.ignoresSafeArea())
            .font(SharpitTypography.body)
            .foregroundStyle(SharpitColor.foreground)
    }

    /// Apply to a `Section`: its rows take the panel tone instead of the system grey, which
    /// would sit beside the brand canvas as a foreign colour. A fill only — a grouped row
    /// carries no shadow of its own.
    func sharpitListRows() -> some View {
        modifier(SharpitListRowSurface())
    }
}

private struct SharpitListRowSurface: ViewModifier {
    @Environment(\.sharpitElevation) private var elevation

    func body(content: Content) -> some View {
        content.listRowBackground(SharpitSurfaceStyle.panel.fill(at: elevation))
    }
}

/// A section title in the app's eyebrow voice, so a grouped list reads like the screens
/// around it instead of like a system settings page dropped in.
extension Section where Parent == SharpitEyebrow, Content: View, Footer == EmptyView {
    init(eyebrow: String, @ViewBuilder content: () -> Content) {
        self.init(content: content, header: { SharpitEyebrow(eyebrow) })
    }
}

extension Section where Parent == SharpitEyebrow, Content: View, Footer == SharpitListFooter {
    init(eyebrow: String, footer: String, @ViewBuilder content: () -> Content) {
        self.init(
            content: content,
            header: { SharpitEyebrow(eyebrow) },
            footer: { SharpitListFooter(footer) }
        )
    }
}

/// A section footer in the brand's small face. The system footer would fall back to SF Pro.
struct SharpitListFooter: View {
    let text: String
    var tone: Color = SharpitColor.mutedForeground

    init(_ text: String, tone: Color = SharpitColor.mutedForeground) {
        self.text = text
        self.tone = tone
    }

    var body: some View {
        Text(text)
            .font(SharpitTypography.meta)
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The line of explanation a screen opens with, above its first group — no surface, because
/// it is prose and not a row.
struct SharpitListIntro: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Section {
            Text(text)
                .foregroundStyle(SharpitColor.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Color.clear)
    }
}

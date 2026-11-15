import SwiftUI

/// A `List` as a Clinique sheet (`docs/adr/0035`): the sheet's own white, rows read straight on
/// it and split by hairlines, a section opening on its title — no grey canvas, no card per group.
///
/// Row metrics, swipe actions, separators and Dynamic Type stay the system's (`docs/adr/0008`);
/// only the surface, the margins and the section titles are the app's.
extension View {
    /// Apply to the `List`. The default font and ink are set here so every row label — a
    /// `Label`, a `Toggle`, a `LabeledContent` — reads in the brand body face and text colour
    /// without each one asking; left alone they fall back to SF Pro in system black.
    /// `wash` puts the screen's one wash at the top of the sheet, for a page read on its own.
    @ViewBuilder
    func sharpitGroupedList(wash: CliniqueWash? = nil) -> some View {
        let list = listStyle(.insetGrouped).scrollContentBackground(.hidden)
        if let wash {
            list.cliniqueSheet(wash: wash, height: 240).modifier(SharpitListDress())
        } else {
            list.background(SharpitCanvasBackground()).modifier(SharpitListDress())
        }
    }
}

private struct SharpitListDress: ViewModifier {
    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, 22, for: .scrollContent)
            .listSectionSpacing(.compact)
            .font(SharpitTypography.body)
            .foregroundStyle(SharpitColor.foreground)
            .environment(\.sharpitSectionTitles, true)
    }
}

extension View {
    /// Apply to a `Section`: its rows sit on the sheet, edge to edge of its margins, split by
    /// the app's hairline.
    func sharpitListRows() -> some View {
        listRowBackground(Color.clear)
            // Two points inside the cell, which clips a glyph's overhang at its very edge.
            .listRowInsets(EdgeInsets(top: 10, leading: 2, bottom: 10, trailing: 2))
            .listRowSeparatorTint(SharpitColor.divider)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

extension EnvironmentValues {
    /// Inside a Clinique list a section marker is the section's title, not a caption.
    @Entry var sharpitSectionTitles = false
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
    var tone: Color = SharpitColor.slate

    init(_ text: String, tone: Color = SharpitColor.slate) {
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

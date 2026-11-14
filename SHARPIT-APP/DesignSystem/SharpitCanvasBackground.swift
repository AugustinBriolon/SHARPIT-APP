import SwiftUI

/// The page: the sheet's own colour, white on light and the card tone on dark
/// (SHARPIT-WEBAPP ADR-131). A screen adds its one wash with `cliniqueSheet(wash:)`.
struct SharpitCanvasBackground: View {
    @Environment(\.sharpitElevation) private var elevation

    var body: some View {
        switch elevation {
        case .base: SharpitColor.card.ignoresSafeArea()
        case .sheet: SharpitElevatedColor.sheet.ignoresSafeArea()
        }
    }
}

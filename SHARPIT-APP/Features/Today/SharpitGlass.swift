import SwiftUI

extension View {
    @ViewBuilder
    func sharpitGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func sharpitGlassCard() -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}

struct SharpitEyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

struct ScrollUnderGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

struct LiquidNavChrome: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

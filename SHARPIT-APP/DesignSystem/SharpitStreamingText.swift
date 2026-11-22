import SwiftUI

/// Text being written by the coach, drawn up to a soft front: the glyphs behind it are ink, the
/// last few fade toward it, and nothing shows past it. The front follows the text as it grows,
/// so words come up out of the page rather than being typed onto it.
nonisolated struct SharpitFadeFrontRenderer: TextRenderer {
    /// How many glyphs are revealed; the `edge` before it are still fading in.
    var front: Double

    /// The width of the fade, in glyphs: about three words.
    static let edge: Double = 18

    var animatableData: Double {
        get { front }
        set { front = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0.0
        for line in layout {
            for run in line {
                let count = Double(run.count)
                defer { index += count }
                // Wholly behind the fade: one draw, as the system would.
                if front - (index + count) >= Self.edge {
                    context.draw(run)
                    continue
                }
                // Wholly ahead of the front: not there yet.
                if front <= index { continue }
                var glyph = index
                for slice in run {
                    let opacity = min(1, max(0, (front - glyph) / Self.edge))
                    glyph += 1
                    guard opacity > 0 else { continue }
                    var faded = context
                    faded.opacity = opacity
                    faded.draw(slice)
                }
            }
        }
    }
}

extension View {
    /// A `Text` of `count` characters that fades in as it is written (`isStreaming`), and is
    /// plain text again once it has settled. Text that was already there — a conversation
    /// opened from history — never fades.
    func sharpitStreamFade(count: Int, isStreaming: Bool) -> some View {
        modifier(SharpitStreamFade(count: count, isStreaming: isStreaming))
    }

    /// A block that is not prose — a table, a rule, a list's marker — arriving in an answer
    /// being written: it fades in once, where prose fades glyph by glyph.
    func sharpitStreamArrival(isStreaming: Bool) -> some View {
        modifier(SharpitStreamArrival(isStreaming: isStreaming))
    }
}

private struct SharpitStreamFade: ViewModifier {
    let count: Int
    let isStreaming: Bool

    /// Where the fade front is; nil once the text has settled and is drawn by the system.
    @State private var front: Double?

    init(count: Int, isStreaming: Bool) {
        self.count = count
        self.isStreaming = isStreaming
        // Only text born while the coach writes starts hidden.
        _front = State(initialValue: isStreaming ? 0 : nil)
    }

    private nonisolated struct Beat: Equatable {
        let count: Int
        let isStreaming: Bool
    }

    func body(content: Content) -> some View {
        Group {
            if let front {
                content.textRenderer(SharpitFadeFrontRenderer(front: front))
            } else {
                content
            }
        }
        .task(id: Beat(count: count, isStreaming: isStreaming)) {
            guard let current = front else { return }
            // The front runs to the end of what is written, at a pace that follows the stream:
            // each new word retargets it rather than restarting it.
            withAnimation(.linear(duration: 0.4)) { front = max(current, Double(count)) }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            // No more words for a moment: the last ones finish coming up.
            withAnimation(.easeOut(duration: 0.45)) {
                front = max(front ?? 0, Double(count) + SharpitFadeFrontRenderer.edge)
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, !isStreaming else { return }
            front = nil
        }
    }
}

private struct SharpitStreamArrival: ViewModifier {
    @State private var isVisible: Bool

    init(isStreaming: Bool) {
        _isVisible = State(initialValue: !isStreaming)
    }

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                guard !isVisible else { return }
                withAnimation(SharpitMotion.fade) { isVisible = true }
            }
    }
}

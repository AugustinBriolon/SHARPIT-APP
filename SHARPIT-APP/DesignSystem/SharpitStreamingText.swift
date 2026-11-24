import SwiftUI

/// Text being written by the coach, revealed line by line: a line fades in whole as the front
/// reaches it, and the words that then join it are simply there. Glyph by glyph (2026-11-22) read
/// as slow: the eye waited on every word. A line at a time keeps the arrival soft and the answer
/// as fast as the stream (the athlete's call, 2026-11-24).
nonisolated struct SharpitFadeFrontRenderer: TextRenderer {
    /// How many glyphs the front has passed; a line starts fading in when it reaches its first one.
    var front: Double

    /// How far the front runs into a line before the line is fully there, in glyphs.
    static let edge: Double = 10

    var animatableData: Double {
        get { front }
        set { front = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var index = 0.0
        for line in layout {
            let count = line.reduce(0.0) { $0 + Double($1.count) }
            defer { index += count }
            let opacity = Self.opacity(front: front, lineStart: index)
            guard opacity > 0 else { continue }
            var shown = context
            shown.opacity = opacity
            shown.draw(line)
        }
    }

    /// 0 until the front reaches the line, 1 once it is `edge` glyphs into it.
    static func opacity(front: Double, lineStart: Double) -> Double {
        min(1, max(0, (front - lineStart) / edge))
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
    /// being written: it fades in once, as each line of prose does.
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
            withAnimation(.linear(duration: 0.22)) { front = max(current, Double(count)) }
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            // No more words for a moment: the last ones finish coming up.
            withAnimation(.easeOut(duration: 0.25)) {
                front = max(front ?? 0, Double(count) + SharpitFadeFrontRenderer.edge)
            }
            try? await Task.sleep(for: .milliseconds(300))
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

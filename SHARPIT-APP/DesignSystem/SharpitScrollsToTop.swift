import SwiftUI

extension View {
    /// On a scroll view that shows one day or one week: when the day or week changes, the new one
    /// opens at its top, at once — never at the depth the previous one was read to, and never with
    /// a scroll back up (the athlete's call, 2026-11-25).
    func scrollsToTop(whenChanged key: some Hashable) -> some View {
        modifier(ScrollsToTopOnChange(key: key))
    }
}

private struct ScrollsToTopOnChange<Key: Hashable>: ViewModifier {
    let key: Key
    @State private var position = ScrollPosition(edge: .top)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onChange(of: key) { _, _ in
                var jump = Transaction()
                jump.disablesAnimations = true
                withTransaction(jump) { position.scrollTo(edge: .top) }
            }
    }
}

import SwiftUI
import UIKit

/// On a screen that shows one day, a horizontal swipe means two things depending on where it
/// starts: from the left edge, back (the system's pop); anywhere else, the day before (to the
/// right) or the day after (to the left). iOS 26 pops from anywhere on the screen, so these
/// screens keep its edge gesture only.
nonisolated enum DaySwipe {
    enum Step: Equatable { case previous, next }

    /// The band along the left edge that stays the system's back gesture.
    static let edgeWidth: CGFloat = 28
    /// A day turns past this horizontal travel…
    static let minimumTravel: CGFloat = 60
    /// …when the swipe is clearly more sideways than vertical (scrolling wins otherwise).
    static let dominance: CGFloat = 1.6

    static func step(startX: CGFloat, translation: CGSize) -> Step? {
        guard startX > edgeWidth else { return nil }
        let dx = translation.width
        guard abs(dx) >= minimumTravel, abs(dx) >= abs(translation.height) * dominance else { return nil }
        return dx > 0 ? .previous : .next
    }

    /// The day a step lands on; never past today.
    static func day(after step: Step, from day: Date, today: Date = .now, calendar: Calendar = .current) -> Date? {
        let offset = step == .previous ? -1 : 1
        guard let target = calendar.date(byAdding: .day, value: offset, to: day) else { return nil }
        if step == .next, calendar.startOfDay(for: target) > calendar.startOfDay(for: today) { return nil }
        return target
    }
}

private struct DaySwipeModifier: ViewModifier {
    let day: Date
    let onSelect: (Date) -> Void

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 24, coordinateSpace: .global)
                    .onEnded { value in
                        guard let step = DaySwipe.step(startX: value.startLocation.x, translation: value.translation),
                              let target = DaySwipe.day(after: step, from: day)
                        else { return }
                        onSelect(target)
                    }
            )
            .background(EdgeOnlyPopGesture())
    }
}

extension View {
    /// Swipe right for the day before, left for the day after; back stays on the left edge.
    func daySwipe(day: Date, onSelect: @escaping (Date) -> Void) -> some View {
        modifier(DaySwipeModifier(day: day, onSelect: onSelect))
    }
}

/// Turns off iOS 26's pop-from-anywhere while the screen shows, so a swipe in the middle
/// changes the day; the edge pop is untouched.
private struct EdgeOnlyPopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            setContentPop(enabled: false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setContentPop(enabled: true)
        }

        private func setContentPop(enabled: Bool) {
            if #available(iOS 26.0, *) {
                navigationController?.interactiveContentPopGestureRecognizer?.isEnabled = enabled
            }
        }
    }
}

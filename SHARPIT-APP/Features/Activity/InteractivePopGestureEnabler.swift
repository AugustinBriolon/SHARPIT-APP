import SwiftUI
import UIKit

/// Re-enables the system interactive pop gesture (swipe from left edge) when
/// `.toolbar(.hidden, for: .navigationBar)` is active.
///
/// By default, UIKit disables `interactivePopGestureRecognizer` when the navigation
/// bar is hidden. This representable hooks into the hosting navigation controller's
/// gesture recognizer and restores swipe-to-dismiss behavior smoothly without breaking
/// navigation stack state.
struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> PopGestureController {
        PopGestureController()
    }

    func updateUIViewController(_ uiViewController: PopGestureController, context: Context) {}

    final class PopGestureController: UIViewController, UIGestureRecognizerDelegate {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachGestureRecognizer()
            // A back swipe let go half-way brings the page back: its touches with it.
            parent?.view.isUserInteractionEnabled = true
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            guard isMovingFromParent || navigationController == nil else { return }
            lastNavigation?.interactivePopGestureRecognizer?.removeTarget(self, action: #selector(backSwipeMoved(_:)))
            if #available(iOS 26.0, *) {
                lastNavigation?.interactiveContentPopGestureRecognizer?.removeTarget(self, action: #selector(backSwipeMoved(_:)))
            }
        }

        /// Kept to take the targets back once popped, when `navigationController` is already nil.
        private weak var lastNavigation: UINavigationController?

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            // Leave navigation controller gesture clean if popped
            if isMovingFromParent {
                navigationController?.interactivePopGestureRecognizer?.delegate = nil
            }
        }

        private func attachGestureRecognizer() {
            guard let nav = navigationController else { return }
            lastNavigation = nav
            nav.interactivePopGestureRecognizer?.isEnabled = true
            nav.interactivePopGestureRecognizer?.delegate = self
            // Idempotent: adding the same target and action twice keeps one.
            nav.interactivePopGestureRecognizer?.addTarget(self, action: #selector(backSwipeMoved(_:)))
            if #available(iOS 26.0, *) {
                nav.interactiveContentPopGestureRecognizer?.addTarget(self, action: #selector(backSwipeMoved(_:)))
            }
        }

        /// The page follows the finger back, so the finger lifts over the very control it
        /// landed on and that control would fire on the page returned to. Turning the page's
        /// touches off for the swipe cancels the press; they come back when it ends.
        @objc private func backSwipeMoved(_ recognizer: UIGestureRecognizer) {
            guard let page = parent?.view ?? navigationController?.topViewController?.view else { return }
            page.isUserInteractionEnabled = BackSwipeTouches.allowed(during: recognizer.state)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let nav = navigationController else { return false }
            // Only allow edge pop if there's more than 1 view controller on the stack
            return nav.viewControllers.count > 1
        }

        /// A press waits for the edge swipe to fail — at once when the touch is not at the edge —
        /// so a swipe that starts on a control pops the page instead of being held by its press.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            !BackSwipeTouches.sharesWith(scrollPan: otherGestureRecognizer.view is UIScrollView)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Alongside a scroll view's own pan only. With anything else — a SwiftUI button's
            // press above all — the swipe must win alone: recognised together, a full-width row
            // kept its press through the whole swipe and fired when the finger lifted.
            BackSwipeTouches.sharesWith(scrollPan: otherGestureRecognizer.view is UIScrollView)
        }
    }
}

nonisolated enum BackSwipeTouches {
    /// The back swipe runs with a scroll view's pan, and with nothing else.
    static func sharesWith(scrollPan: Bool) -> Bool { scrollPan }

    /// A page takes no touch while a back swipe is under way.
    static func allowed(during state: UIGestureRecognizer.State) -> Bool {
        switch state {
        case .began, .changed: false
        default: true
        }
    }
}

extension View {
    /// Restores the interactive swipe-from-left edge pop gesture when the navigation bar is hidden.
    func enableInteractivePopGesture() -> some View {
        background(InteractivePopGestureEnabler())
    }
}

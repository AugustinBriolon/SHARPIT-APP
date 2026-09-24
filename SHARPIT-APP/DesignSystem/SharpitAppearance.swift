import SwiftUI
import UIKit

/// The colour scheme, chosen per iPhone: it is how this screen should look, not a fact about the
/// athlete, so it stays on the device and never reaches the server.
nonisolated enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    static let storageKey = "sharpit.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// Nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Applies the athlete's colour scheme to every window of the app.
///
/// Through the window's `overrideUserInterfaceStyle` rather than SwiftUI's
/// `preferredColorScheme`: a sheet is its own presentation, and a preference set on the root
/// reached an open sheet only when it was reopened — switching Apparence left the page itself in
/// the old scheme. The window override reaches everything it presents at once, and going back
/// to « Système » really clears it, which `preferredColorScheme(nil)` does not always do.
struct SharpitAppearanceModifier: ViewModifier {
    @AppStorage(AppearancePreference.storageKey) private var appearance: AppearancePreference = .system

    func body(content: Content) -> some View {
        content.onChange(of: appearance, initial: true) { _, preference in
            SharpitAppearance.apply(preference)
        }
    }
}

enum SharpitAppearance {
    static func apply(_ preference: AppearancePreference) {
        let style: UIUserInterfaceStyle = switch preference {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows where window.overrideUserInterfaceStyle != style {
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

extension View {
    /// Once, at the app root.
    func sharpitAppearance() -> some View {
        modifier(SharpitAppearanceModifier())
    }
}

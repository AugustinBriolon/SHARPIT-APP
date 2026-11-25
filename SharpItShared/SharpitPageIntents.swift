import AppIntents
import Foundation

/// How a Siri shortcut or a Control Center button opens a page of the app. Not an
/// `OpenURLIntent`: `sharpit.app` claims only its sign-in callbacks for the app, so the system
/// opened any other `sharpit.app` link in Safari (2026-11-25). These intents run in the app
/// (`openAppWhenRun`, compiled into the app and the widget extension both) and hand the page to
/// whatever the app registered — its link inbox, set in `SharpitApp.init` before any intent runs.
nonisolated enum SharpitPageOpener {
    @MainActor static var open: ((URL) -> Void)?

    /// A page asked for before the app registered its inbox waits here, taken once it does.
    @MainActor private(set) static var pending: URL?

    @MainActor static func request(_ url: URL) {
        if let open { open(url) } else { pending = url }
    }

    @MainActor static func register(_ handler: @escaping (URL) -> Void) {
        open = handler
        if let pending {
            self.pending = nil
            handler(pending)
        }
    }
}

/// Control Center's « Demander au coach ».
struct OpenCoachControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Demander au coach"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharpitPageOpener.request(WidgetSnapshot.link("/coach"))
        return .result()
    }
}

/// Control Center's « Scanner un produit ».
struct OpenFoodScannerControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Scanner un produit"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharpitPageOpener.request(WidgetSnapshot.link("/nutrition/scan"))
        return .result()
    }
}

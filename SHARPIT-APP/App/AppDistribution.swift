import Foundation

/// How this copy of the app was installed: from Xcode, TestFlight or the App Store.
nonisolated enum AppDistribution {
    static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// A TestFlight install carries a sandbox receipt; an App Store install a production one.
    static let isTestFlight = Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
}

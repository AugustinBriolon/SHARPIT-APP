import ClerkKit
import SwiftUI

@main
struct SharpitApp: App {
    init() {
        Clerk.configure(publishableKey: ClerkConfiguration.publishableKey)
    }

    var body: some Scene {
        WindowGroup {
            AuthGate {
                RootView()
            }
            .environment(Clerk.shared)
        }
    }
}

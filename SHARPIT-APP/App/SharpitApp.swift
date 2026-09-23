import ClerkKit
import ClerkKitUI
import SwiftData
import SwiftUI

@main
struct SharpitApp: App {
    private let modelContainer: ModelContainer

    init() {
        SharpitFonts.register()
        Clerk.configure(publishableKey: ClerkConfiguration.publishableKey)
        do {
            modelContainer = try SharpitPersistence.makeContainer()
        } catch {
            // Last-resort in-memory store so a disk failure still launches.
            modelContainer = try! SharpitPersistence.makeContainer(inMemory: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            AuthGate {
                RootView()
            }
            .environment(Clerk.shared)
            .environment(\.clerkTheme, .sharpit)
        }
        .modelContainer(modelContainer)
    }
}

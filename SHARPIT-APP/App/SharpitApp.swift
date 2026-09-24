import ClerkKit
import ClerkKitUI
import SwiftData
import SwiftUI

@main
struct SharpitApp: App {
    @UIApplicationDelegateAdaptor(SharpitAppDelegate.self) private var appDelegate
    private let modelContainer: ModelContainer

    init() {
        SharpitFonts.register()
        Clerk.configure(publishableKey: ClerkConfiguration.publishableKey)
        // Before the container, so its first CloudKit setup event is heard.
        CloudSyncMonitor.shared.start()
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
                // The legal wall, then the web's onboarding, before a new account sees the tabs.
                AccountGate {
                    RootView()
                }
            }
            .environment(Clerk.shared)
            .environment(\.clerkTheme, .sharpit)
            // Per iPhone, never synced (Paramètres → Apparence).
            .sharpitAppearance()
            .onOpenURL { url in
                Task {
                    try? await Clerk.shared.handle(url)
                }
            }
        }
        .modelContainer(modelContainer)
    }
}

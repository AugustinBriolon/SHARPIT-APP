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
                // A new account answers the web's onboarding before it sees the tabs.
                OnboardingGate {
                    RootView()
                }
            }
            .environment(Clerk.shared)
            .environment(\.clerkTheme, .sharpit)
            .onOpenURL { url in
                Task {
                    try? await Clerk.shared.handle(url)
                }
            }
        }
        .modelContainer(modelContainer)
    }
}

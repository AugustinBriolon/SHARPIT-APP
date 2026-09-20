import ClerkKit
import ClerkKitUI
import SwiftUI

struct AuthGate<SignedIn: View>: View {
    @Environment(Clerk.self) private var clerk
    @State private var authIsPresented = false
    var signedIn: () -> SignedIn

    var body: some View {
        Group {
            if clerk.user != nil {
                signedIn()
            } else {
                ContentUnavailableView {
                    Label("SharpIt", systemImage: "figure.run")
                } description: {
                    Text("Connecte-toi pour ouvrir ton résumé du jour.")
                } actions: {
                    Button("Se connecter") {
                        authIsPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .prefetchClerkImages()
            }
        }
        .sheet(isPresented: $authIsPresented) {
            AuthView()
        }
    }
}

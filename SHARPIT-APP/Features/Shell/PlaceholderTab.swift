import SwiftUI

struct PlaceholderTab: View {
    let title: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: "clock", description: Text("Bientôt"))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .modifier(LiquidNavChrome())
        }
    }
}

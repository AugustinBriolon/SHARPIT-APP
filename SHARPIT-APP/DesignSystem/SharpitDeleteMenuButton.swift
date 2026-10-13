import SwiftUI

/// « Supprimer » inside a menu or context menu. RootView's `.tint(primary)` otherwise paints the
/// trash green while the destructive role paints the title red; both go through the destructive token.
struct SharpitDeleteMenuButton: View {
    var title: String = "Supprimer"
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: "trash")
            }
            .foregroundStyle(SharpitColor.destructive)
        }
    }
}

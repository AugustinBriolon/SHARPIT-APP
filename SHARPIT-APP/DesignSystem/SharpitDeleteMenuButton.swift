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

/// Destructive list swipe. Same RootView tint leak paints the trash green on a non-red chip;
/// pinning `.tint(destructive)` restores white glyph on red background.
struct SharpitSwipeDeleteButton: View {
    var title: String = "Supprimer"
    var systemImage: String = "trash"
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: systemImage)
        }
        .tint(SharpitColor.destructive)
    }
}

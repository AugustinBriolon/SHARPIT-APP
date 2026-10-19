import SwiftUI

/// « Supprimer » inside a menu or context menu, the trash as red as its title. A menu draws its
/// icons as templates in the app's tint and ignores any SwiftUI colour, so the glyph goes in
/// already tinted (`alwaysOriginal`).
struct SharpitDeleteMenuButton: View {
    var title: String = String(localized: "Supprimer")
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label {
                Text(title)
            } icon: {
                Image(uiImage: Self.redTrash)
            }
        }
    }

    private static let redTrash: UIImage = {
        let image = UIImage(systemName: "trash") ?? UIImage()
        return image.withTintColor(UIColor(SharpitColor.destructive), renderingMode: .alwaysOriginal)
    }()
}

/// Destructive list swipe. Same RootView tint leak paints the trash green on a non-red chip;
/// pinning `.tint(destructive)` restores white glyph on red background.
struct SharpitSwipeDeleteButton: View {
    var title: String = String(localized: "Supprimer")
    var systemImage: String = "trash"
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label(title, systemImage: systemImage)
        }
        .tint(SharpitColor.destructive)
    }
}

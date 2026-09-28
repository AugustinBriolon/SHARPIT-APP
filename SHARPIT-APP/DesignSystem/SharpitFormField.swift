import SwiftUI
import UIKit

/// The small uppercase label above a field or a row of choices.
struct SharpitFieldLabel: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(SharpitTypography.label)
            .tracking(SharpitTypography.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(SharpitColor.mutedForeground)
    }
}

/// A labelled text field on a panel.
struct SharpitFormField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    init(_ title: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) {
        self.title = title
        self.placeholder = placeholder
        _text = text
        self.keyboard = keyboard
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SharpitFieldLabel(title)
            TextField(placeholder, text: $text)
                .font(SharpitTypography.body)
                .foregroundStyle(SharpitColor.foreground)
                .keyboardType(keyboard)
                .submitLabel(.done)
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
    }
}

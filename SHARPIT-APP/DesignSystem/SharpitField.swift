import SwiftUI

/// One value the athlete types, on a panel: the name, the entry, a hint or the reason it
/// was refused.
///
/// The label sits above the field rather than beside it, as the web's forms do: a threshold
/// name is longer than the number it holds, and a two-column row would push `Vitesse
/// critique natation` onto two lines beside a four-character value.
struct SharpitField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var unit: String?
    /// The entry it expects — a pace is typed with a colon, a weight with a comma.
    var keyboard: UIKeyboardType = .numberPad
    /// A quiet line under the field. Replaced by `error` when the entry is refused.
    var hint: String?
    var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.xxs) {
            Text(label)
                .font(SharpitTypography.label)
                .tracking(SharpitTypography.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(SharpitColor.mutedForeground)
            HStack(alignment: .firstTextBaseline, spacing: SharpitSpacing.xs) {
                TextField(placeholder, text: $text)
                    .font(SharpitTypography.data)
                    .tracking(SharpitTypography.dataTracking)
                    .keyboardType(keyboard)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                if let unit {
                    Text(unit)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .padding(.horizontal, SharpitSpacing.sm)
            .padding(.vertical, SharpitSpacing.xs + 2)
            .sharpitSurface(.chip)
            if let error {
                Text(error)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let hint {
                Text(hint)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A group of fields on one panel, under a title — the form counterpart of
/// `SharpitHubGroup`.
struct SharpitFieldGroup<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let fields: Content

    init(_ title: String, note: String? = nil, @ViewBuilder fields: () -> Content) {
        self.title = title
        self.note = note
        self.fields = fields()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SharpitSpacing.sm) {
            SharpitEyebrow(title)
            VStack(alignment: .leading, spacing: SharpitSpacing.md) {
                fields
                if let note {
                    Text(note)
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(SharpitSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sharpitSurface(.panel)
        }
    }
}

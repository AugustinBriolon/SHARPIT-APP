import SwiftUI

/// The exercise a note sheet is open on.
struct ExerciseNoteTarget: Identifiable, Equatable {
    let name: String
    var id: String { name }
}

/// « Ma note » on one exercise: a cue, a setting, a pain to watch, kept for every session where
/// the exercise comes back and read by the coach (SHARPIT ADR-146). The save waits for the
/// server; a refusal is said under the field, the text left as typed. Emptied, the note goes.
struct ExerciseNoteSheet: View {
    let name: String
    let initial: String
    let onSave: (String) async throws -> Void

    @State private var text: String
    @State private var isSaving = false
    @State private var failure: String?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// The server keeps 500 characters.
    static let limit = 500

    init(name: String, initial: String, onSave: @escaping (String) async throws -> Void) {
        self.name = name
        self.initial = initial
        self.onSave = onSave
        _text = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CliniqueSheetTitle(String(localized: "Ma note"))
                .padding(.horizontal, 24)
                .padding(.top, 30)
            Text(name)
                .font(SharpitTypography.system(size: 15, weight: .regular, relativeTo: .subheadline))
                .foregroundStyle(SharpitColor.slate)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 14)

            TextField(
                String(localized: "Réglage, consigne, gêne à surveiller…"),
                text: $text,
                axis: .vertical
            )
            .font(SharpitTypography.system(size: 17, weight: .regular, relativeTo: .body))
            .lineLimit(3...8)
            .focused($isFocused)
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(SharpitColor.outline, lineWidth: 1))
            .padding(.horizontal, 24)
            .onChange(of: text) { _, value in
                if value.count > Self.limit { text = String(value.prefix(Self.limit)) }
            }

            Text("Elle revient à chaque séance avec cet exercice, et le coach la lit.")
                .font(SharpitTypography.meta)
                .foregroundStyle(SharpitColor.slate)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            if let failure {
                Text(failure)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SharpitColor.card)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { Task { await save() } } label: {
                Group {
                    if isSaving { ProgressView().tint(SharpitColor.primaryForeground) } else { Text("Enregistrer") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CliniqueButtonStyle(kind: .primary, isLarge: true))
            .disabled(isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines) == initial)
            .padding(.horizontal, 16)
            .padding(.vertical, SharpitSpacing.xs)
            .background(SharpitColor.card)
        }
        .cliniqueSheetCross { dismiss() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sharpitSheet()
        .onAppear { isFocused = true }
    }

    private func save() async {
        isSaving = true
        failure = nil
        defer { isSaving = false }
        do {
            try await onSave(text)
            dismiss()
        } catch {
            failure = String(localized: "Note non enregistrée. Réessaie dans un instant.")
        }
    }
}

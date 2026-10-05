import SwiftUI

/// What a screen hands the drawer so the athlete can mark a session key or not (SHARPIT F2: the
/// week's two or three sessions that carry the preparation; missing the others is no missed week).
struct SessionKeyContext {
    let mutator: any PlannedSessionMutating
    let tokenProvider: () async throws -> String
    /// Called once the server has it, so the plan behind shows the tag.
    let onChanged: () -> Void
}

/// The drawer's « Séance clé » switch: moved on the tap, written behind and retried; put back
/// and said in the toast if it fails for good.
@MainActor
@Observable
final class SessionKeyStore {
    private(set) var isKey: Bool
    private let sessionId: String
    private let context: SessionKeyContext

    init(sessionId: String, isKey: Bool, context: SessionKeyContext) {
        self.sessionId = sessionId
        self.isKey = isKey
        self.context = context
    }

    func set(_ on: Bool) async {
        guard on != isKey else { return }
        isKey = on
        do {
            _ = try await SharpitRetry.run {
                try await context.mutator.updateSession(
                    id: sessionId,
                    patch: UpdatePlannedSessionPayload(isKey: on),
                    token: try await context.tokenProvider()
                )
            }
            context.onChanged()
        } catch {
            isKey = !on
            SharpitWriteFailures.shared.report(Self.failureMessage)
        }
    }

    static let failureMessage = "La séance n’a pas pu être marquée. Réessaie dans un instant."
}

/// « Séance clé » in a session's drawer.
struct SessionKeyRow: View {
    @State private var store: SessionKeyStore

    init(sessionId: String, isKey: Bool, context: SessionKeyContext) {
        _store = State(initialValue: SessionKeyStore(sessionId: sessionId, isKey: isKey, context: context))
    }

    var body: some View {
        Toggle(isOn: Binding(get: { store.isKey }, set: { on in Task { await store.set(on) } })) {
            HStack(spacing: SharpitSpacing.sm) {
                Image(systemName: "flag.fill")
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.primary)
                    .frame(width: 28, height: 28)
                    .background(SharpitColor.chipSurface, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Séance clé")
                        .font(SharpitTypography.bodyEmphasis)
                        .foregroundStyle(SharpitColor.foreground)
                    Text("Une des 2 ou 3 séances qui portent ta semaine. Les autres sont un bonus.")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
        }
        .tint(SharpitColor.primary)
        .padding(SharpitSpacing.cardPadding)
        .sharpitSurface(.panel)
    }
}

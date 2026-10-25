import SwiftUI

/// Where a planned session stands on the athlete's Garmin watch.
enum WatchPushState: Equatable {
    case notSent
    case sent
    /// Sent, then moved to another day: the watch still offers the old one.
    case moved

    /// The day is read in the calendar the plan is shown in, as Plan places the session.
    static func of(
        garminWorkoutId: String?,
        scheduledDate: String?,
        sessionDate: Date,
        calendar: Calendar = .current
    ) -> WatchPushState {
        guard garminWorkoutId != nil else { return .notSent }
        let day = calendar.dateComponents([.year, .month, .day], from: sessionDate)
        let key = String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
        return scheduledDate == key ? .sent : .moved
    }

    /// The sports the Training API takes for now (SHARPIT ADR-106): strength and bricks wait.
    static func canSend(type: String?) -> Bool {
        ["RUN", "BIKE", "SWIM"].contains(type?.uppercased() ?? "")
    }
}

/// What the drawer needs to send its session to the watch; nil where it cannot — Garmin not
/// linked, a sport the watch does not take yet.
struct SessionWatchContext {
    let session: V1PlannedSessionItem
    let client: any GarminWorkoutPushing
    let tokenProvider: () async throws -> String
    /// The session reached the watch; the screen reads its plan again.
    let onSent: () -> Void
}

/// « Envoyer sur ma montre » in a session's drawer. Pro-only, as every push to the watch is:
/// a Free athlete sees the teaser in its place.
struct SessionWatchPushRow: View {
    let context: SessionWatchContext

    @Environment(ProStore.self) private var pro: ProStore?
    @Environment(SharpitToastCenter.self) private var toastCenter: SharpitToastCenter?
    @State private var isSending = false
    @State private var isConfirmingResend = false
    /// The day just sent, until the plan read again brings the server's copy.
    @State private var sentDay: String?

    private var state: WatchPushState {
        WatchPushState.of(
            garminWorkoutId: sentDay == nil ? context.session.garminWorkoutId : "sent",
            scheduledDate: sentDay ?? context.session.garminWorkoutScheduledDate,
            sessionDate: context.session.date
        )
    }

    var body: some View {
        if let pro, !pro.isPro {
            SharpitProTeaser(
                title: String(localized: "Sur ta montre"),
                message: String(localized: "Envoie la séance sur ta Garmin, cibles comprises, avec SharpIt Pro.")
            )
        } else {
            DrawerActionRow(symbolName: symbolName, title: title, subtitle: subtitle) {
                if state == .sent {
                    isConfirmingResend = true
                } else {
                    Task { await send(replace: state == .moved) }
                }
            }
            .disabled(isSending)
            .overlay(alignment: .trailing) {
                if isSending {
                    ProgressView()
                        .padding(.trailing, SharpitSpacing.cardPadding + SharpitSpacing.md)
                }
            }
            .confirmationDialog(
                String(localized: "Renvoyer la séance ?"),
                isPresented: $isConfirmingResend,
                titleVisibility: .visible
            ) {
                Button("Renvoyer") { Task { await send(replace: true) } }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("La version déjà sur ta montre est remplacée.")
            }
        }
    }

    private var symbolName: String {
        switch state {
        case .notSent: "paperplane"
        case .sent: "checkmark.circle"
        case .moved: "arrow.triangle.2.circlepath"
        }
    }

    private var title: String {
        switch state {
        case .notSent: String(localized: "Envoyer sur ma montre")
        case .sent: String(localized: "Sur ta montre")
        case .moved: String(localized: "Renvoyer sur ma montre")
        }
    }

    private var subtitle: String {
        switch state {
        case .notSent: String(localized: "Garmin la reçoit à la prochaine synchro de la montre")
        case .sent: String(localized: "Envoyée sur Garmin · touche pour la renvoyer")
        case .moved: String(localized: "Le jour a changé depuis l’envoi")
        }
    }

    private func send(replace: Bool) async {
        guard !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            let receipt = try await context.client.sendToWatch(
                plannedSessionId: context.session.id,
                replace: replace,
                token: try await context.tokenProvider()
            )
            sentDay = receipt.scheduledDate
            toastCenter?.show(
                Self.sentMessage(for: receipt),
                symbol: "checkmark.circle.fill",
                tone: .success,
                autoDismissAfter: 4
            )
            context.onSent()
        } catch {
            toastCenter?.show(
                Self.failureMessage(for: error),
                symbol: "exclamationmark.triangle",
                tone: .error,
                autoDismissAfter: 5
            )
        }
    }

    /// A target sent without guidance is worth saying: the watch will not hold the athlete to it.
    static func sentMessage(for receipt: V1GarminWorkoutReceipt) -> String {
        if let warning = receipt.warnings.first {
            return String(localized: "Séance envoyée sur ta montre. \(warning)")
        }
        return String(localized: "Séance envoyée sur ta montre")
    }

    static func failureMessage(for error: Error) -> String {
        if case .message(let text)? = error as? SharpitAPIError { return text }
        return SharpitErrorGuidance.message(for: error, subject: String(localized: "L’envoi sur la montre"))
    }
}

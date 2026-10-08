import SwiftUI

/// Lists Google calendars and saves the write target via `POST /api/v1/google/select-calendar`.
struct GoogleCalendarPickerView: View {
    @State private var store: GoogleCalendarPickerStore
    private let onSelected: () -> Void

    @Environment(\.dismiss) private var dismiss

    init(
        tokenProvider: @escaping () async throws -> String,
        client: any GoogleCalendarsServing = GoogleCalendarsClient(),
        onSelected: @escaping () -> Void = {}
    ) {
        _store = State(initialValue: GoogleCalendarPickerStore(client: client, tokenProvider: tokenProvider))
        self.onSelected = onSelected
    }

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                calendarList(store.calendars.isEmpty ? V1GoogleCalendar.placeholders : store.calendars)
                    .redacted(reason: store.calendars.isEmpty ? .placeholder : [])
                    .allowsHitTesting(false)
                    .accessibilityLabel("Chargement des calendriers Google")
            case .failed(.needsReconnect(let message)):
                reconnectState(message)
            case .failed(.load(let message)) where store.calendars.isEmpty:
                SharpitStateMessage.failed(message) { Task { await store.load() } }
            case .failed(.load(let message)):
                calendarList(store.calendars, loadFailure: message)
            case .ready, .selecting:
                calendarList(store.calendars)
            }
        }
        .navigationTitle("Calendrier Google")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
    }

    private func calendarList(_ items: [V1GoogleCalendar], loadFailure: String? = nil) -> some View {
        List {
            if let loadFailure {
                Section {
                    Label(loadFailure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(SharpitColor.signalCaution)
                    Button("Réessayer") { Task { await store.load() } }
                }
                .sharpitListRows()
            }
            Section {
                ForEach(items) { calendar in
                    Button {
                        Task {
                            guard await store.select(calendar) else { return }
                            onSelected()
                            dismiss()
                        }
                    } label: {
                        calendarRow(calendar)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.phase == .selecting)
                }
            } footer: {
                SharpitListFooter(
                    "SHARPIT écrit tes créneaux planifiés dans ce calendrier Google. Tu peux le changer à tout moment."
                )
            }
            .sharpitListRows()
        }
        .sharpitGroupedList()
        .opacity(store.phase == .selecting ? 0.65 : 1)
    }

    private func calendarRow(_ calendar: V1GoogleCalendar) -> some View {
        HStack(spacing: SharpitSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(calendar.summary)
                    .font(SharpitTypography.bodyEmphasis)
                    .foregroundStyle(SharpitColor.foreground)
                if calendar.primary {
                    Text("Agenda principal Google")
                        .font(SharpitTypography.meta)
                        .foregroundStyle(SharpitColor.mutedForeground)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if calendar.isTarget {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(SharpitColor.primary)
                    .accessibilityLabel("Calendrier sélectionné")
            }
        }
        .padding(.vertical, SharpitSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func reconnectState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Session Google expirée", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Link(
                "Relier sur sharpit.app",
                destination: APIConfiguration.webOrigin.appending(path: PushNotificationManager.sourcesPath)
            )
            Button("Réessayer") { Task { await store.load() } }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SharpitCanvasBackground())
    }
}

private extension V1GoogleCalendar {
    static let placeholders: [V1GoogleCalendar] = (0..<3).map { index in
        V1GoogleCalendar(id: "placeholder-\(index)", summary: "Mon agenda", primary: index == 0, isTarget: index == 0)
    }
}

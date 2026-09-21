import SwiftUI

/// The frame every day drill-down shares: the day picker fixed on top, then the day's
/// content, or its loading, empty, failed or signed-out state. The content dims while
/// another day loads over it.
struct DayDetailScaffold<Payload: V1DayResource, Content: View>: View {
    let title: String
    let emptySymbol: String
    let unavailableTitle: String
    let store: DayResourceStore<Payload>
    @ViewBuilder let content: (Payload) -> Content

    var body: some View {
        VStack(spacing: 0) {
            DayDetailDatePicker(
                selectedDay: store.selectedDay,
                hasData: store.hasData(on:)
            ) { day in
                Task { await store.select(day) }
            }
            phaseView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(store.isSwitchingDay ? 0.45 : 1)
                .animation(SharpitMotion.fade, value: store.isSwitchingDay)
        }
        .background(SharpitCanvasBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
    }

    @ViewBuilder
    private var phaseView: some View {
        switch store.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let payload):
            ScrollView {
                content(payload)
                    .padding(.top, SharpitSpacing.md)
            }
            .modifier(ScrollUnderGlass())
            .refreshable { await store.load() }
        case .empty(let empty):
            ContentUnavailableView(
                empty.title,
                systemImage: emptySymbol,
                description: empty.message.map(Text.init)
            )
        case .failed(let message):
            ContentUnavailableView {
                Label(unavailableTitle, systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("Réessayer") { Task { await store.load() } }
            }
        case .unauthorized:
            ContentUnavailableView("Session expirée", systemImage: "person.crop.circle.badge.exclamationmark")
        }
    }
}

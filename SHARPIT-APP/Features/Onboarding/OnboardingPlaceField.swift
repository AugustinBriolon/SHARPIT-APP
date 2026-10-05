import MapKit
import Observation
import SwiftUI

/// One suggested place, as the completer named it.
nonisolated struct PlaceSuggestion: Hashable, Sendable {
    let title: String
    let subtitle: String

    /// « Paris, France » — the place as it will be stored on the goal.
    var label: String { subtitle.isEmpty ? title : "\(title), \(subtitle)" }
}

/// Places matching what is typed, from MapKit's completer — towns and cities, not every shop.
@MainActor
@Observable
final class PlaceSuggestions: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [PlaceSuggestion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.addressFilter = MKAddressFilter(including: [.locality, .administrativeArea, .country])
    }

    func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            results = []
            completer.cancel()
            return
        }
        completer.queryFragment = query
    }

    func clear() {
        results = []
        completer.cancel()
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results.prefix(5).map { PlaceSuggestion(title: $0.title, subtitle: $0.subtitle) }
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}

/// A place typed with suggestions under it: picking one fills the field, typing freely still
/// works for a place MapKit does not know.
struct OnboardingPlaceField: View {
    let title: String
    @Binding var text: String

    @State private var suggestions = PlaceSuggestions()
    /// The label of the place picked, so filling the field with it does not search again.
    @State private var pickedText: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SharpitFieldLabel(title)
            HStack(spacing: SharpitSpacing.xs) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(SharpitColor.mutedForeground)
                TextField("Cherche une ville", text: $text)
                    .font(SharpitTypography.body)
                    .foregroundStyle(SharpitColor.foreground)
                    .textContentType(.addressCity)
                    .submitLabel(.done)
                    .focused($focused)
            }
            if focused, pickedText != text, !suggestions.results.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions.results, id: \.self) { place in
                        Button {
                            let label = place.label
                            pickedText = label
                            text = label
                            suggestions.clear()
                            focused = false
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(place.title)
                                    .font(SharpitTypography.bodyEmphasis)
                                    .foregroundStyle(SharpitColor.foreground)
                                if !place.subtitle.isEmpty {
                                    Text(place.subtitle)
                                        .font(SharpitTypography.meta)
                                        .foregroundStyle(SharpitColor.mutedForeground)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, SharpitSpacing.xs)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, SharpitSpacing.xxs)
                .transition(.opacity)
            }
        }
        .padding(SharpitSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sharpitSurface(.panel)
        .animation(SharpitMotion.fade, value: suggestions.results.count)
        .onChange(of: text) { _, value in
            guard value != pickedText else { return }
            pickedText = nil
            suggestions.search(value)
        }
    }
}

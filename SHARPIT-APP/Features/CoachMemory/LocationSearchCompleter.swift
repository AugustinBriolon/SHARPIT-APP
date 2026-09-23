import Foundation
import MapKit
import Observation

/// A lightweight wrapper around a MapKit search completion result,
/// holding only the strings needed for display and selection.
struct LocationSuggestion: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String

    var displayName: String {
        [title, subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

@MainActor
@Observable
final class LocationSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                suggestions = []
            } else {
                completer.queryFragment = trimmed
            }
        }
    }

    private(set) var suggestions: [LocationSuggestion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Extract Sendable values immediately on this thread before crossing actor boundaries
        let extracted: [LocationSuggestion] = completer.results.map { completion in
            LocationSuggestion(
                id: "\(completion.title)__\(completion.subtitle)",
                title: completion.title,
                subtitle: completion.subtitle
            )
        }
        Task { @MainActor in
            self.suggestions = extracted
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.suggestions = []
        }
    }

    func clear() {
        query = ""
        suggestions = []
    }
}

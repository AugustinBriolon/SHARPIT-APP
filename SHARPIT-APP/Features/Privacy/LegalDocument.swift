import SafariServices
import SwiftUI

/// The two documents the athlete accepts. Their text and version live on the web
/// (`docs/legal`, `CURRENT_PRIVACY_VERSION`), so the app opens the published pages rather
/// than carrying a copy that would drift the first time the web amends a clause.
enum LegalDocument: String, CaseIterable, Identifiable, Sendable {
    case terms
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .terms: "Conditions d'utilisation"
        case .privacy: "Politique de confidentialité"
        }
    }

    var symbol: String {
        switch self {
        case .terms: "doc.text.fill"
        case .privacy: "hand.raised.fill"
        }
    }

    var url: URL {
        APIConfiguration.baseURL.appending(path: "/\(rawValue)")
    }
}

/// A published document, read inside the app: the athlete accepting it never leaves the
/// wall, and Done brings them back exactly where they were.
struct LegalDocumentSheet: View {
    let document: LegalDocument

    var body: some View {
        SafariView(url: document.url)
            .ignoresSafeArea()
            .accessibilityLabel(document.title)
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context _: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredControlTintColor = UIColor(SharpitColor.primary)
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_: SFSafariViewController, context _: Context) {}
}

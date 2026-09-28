import SwiftUI
import WebKit

/// The session cookie MyFitnessPal sets once the athlete is signed in — what the web asks the
/// athlete to copy by hand from their browser's developer tools. Here the athlete signs in on
/// MFP's own site, in the app, and the app reads it: SHARPIT never sees the password.
nonisolated enum MyFitnessPalSession {
    static let cookieName = "__Secure-next-auth.session-token"
    static let loginURL = URL(string: "https://www.myfitnesspal.com/account/login")!

    /// The whole cookie, or its chunks (`.0`, `.1`…) joined in order, as next-auth splits a
    /// large one. Nil until the athlete is signed in.
    static func sessionToken(from cookies: [(name: String, value: String)]) -> String? {
        if let whole = cookies.first(where: { $0.name == cookieName }), !whole.value.isEmpty {
            return whole.value
        }
        let chunks = cookies
            .compactMap { cookie -> (Int, String)? in
                guard cookie.name.hasPrefix(cookieName + "."),
                      let index = Int(cookie.name.dropFirst(cookieName.count + 1))
                else { return nil }
                return (index, cookie.value)
            }
            .sorted { $0.0 < $1.0 }
        guard !chunks.isEmpty, chunks.map(\.0) == Array(0..<chunks.count) else { return nil }
        return chunks.map(\.1).joined()
    }
}

/// Sign in to MyFitnessPal and link it to SHARPIT, in one sheet.
struct MyFitnessPalConnectSheet: View {
    let client: any MyFitnessPalServing
    let tokenProvider: () async throws -> String
    let onConnected: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLinking = false
    @State private var failure: String?
    @State private var reloadID = UUID()

    var body: some View {
        NavigationStack {
            ZStack {
                MyFitnessPalWebView(onSessionToken: link)
                    .id(reloadID)
                    .opacity(isLinking ? 0.3 : 1)
                if isLinking {
                    VStack(spacing: SharpitSpacing.sm) {
                        ProgressView()
                        Text("Connexion de ton journal alimentaire…")
                            .font(SharpitTypography.bodyEmphasis)
                            .foregroundStyle(SharpitColor.foreground)
                        Text("SharpIt importe tes derniers jours, ça peut prendre une minute.")
                            .font(SharpitTypography.meta)
                            .foregroundStyle(SharpitColor.mutedForeground)
                            .multilineTextAlignment(.center)
                    }
                    .padding(SharpitSpacing.lg)
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle("MyFitnessPal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(isLinking)
    }

    private var footer: some View {
        VStack(spacing: SharpitSpacing.xs) {
            if let failure {
                Text(failure)
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.signalRisk)
                    .multilineTextAlignment(.center)
                Button("Réessayer") {
                    self.failure = nil
                    reloadID = UUID()
                }
                .font(SharpitTypography.bodyEmphasis)
            } else {
                Label("Connecte-toi sur le site de MyFitnessPal. SharpIt ne voit pas ton mot de passe.", systemImage: "lock.fill")
                    .font(SharpitTypography.meta)
                    .foregroundStyle(SharpitColor.mutedForeground)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(SharpitSpacing.md)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func link(_ sessionToken: String) {
        guard !isLinking else { return }
        isLinking = true
        Task {
            defer { isLinking = false }
            do {
                let token = try await tokenProvider()
                try await client.connectMyFitnessPal(sessionToken: sessionToken, token: token)
                SharpitHaptics.play(.success)
                onConnected()
                dismiss()
            } catch {
                failure = (error as? LocalizedError)?.errorDescription
                    ?? "La connexion à MyFitnessPal a échoué."
            }
        }
    }
}

/// MFP's sign-in page in a private web view — nothing is kept once the sheet closes — watching
/// its cookies until the session one appears.
private struct MyFitnessPalWebView: UIViewRepresentable {
    let onSessionToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSessionToken: onSessionToken) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        configuration.websiteDataStore.httpCookieStore.add(context.coordinator)
        context.coordinator.cookieStore = configuration.websiteDataStore.httpCookieStore
        webView.load(URLRequest(url: MyFitnessPalSession.loginURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKHTTPCookieStoreObserver {
        let onSessionToken: (String) -> Void
        weak var cookieStore: WKHTTPCookieStore?
        private var delivered = false

        init(onSessionToken: @escaping (String) -> Void) {
            self.onSessionToken = onSessionToken
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            check(webView.configuration.websiteDataStore.httpCookieStore)
        }

        func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            check(cookieStore)
        }

        private func check(_ store: WKHTTPCookieStore) {
            store.getAllCookies { [weak self] cookies in
                let pairs = cookies
                    .filter { $0.domain.contains("myfitnesspal.com") }
                    .map { (name: $0.name, value: $0.value) }
                guard let self, !self.delivered,
                      let token = MyFitnessPalSession.sessionToken(from: pairs)
                else { return }
                self.delivered = true
                DispatchQueue.main.async { self.onSessionToken(token) }
            }
        }
    }
}

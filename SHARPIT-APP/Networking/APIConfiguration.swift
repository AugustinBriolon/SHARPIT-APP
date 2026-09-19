import Foundation

enum APIConfiguration {
    /// Environment variable read at launch, so the origin can be switched from the Xcode
    /// scheme (Run → Arguments → Environment Variables) without editing or rebuilding.
    ///
    /// Point it at a deployed instance — a Vercel preview, or production — when you do
    /// not want the local chain of Docker → Postgres → `yarn dev` running just to see
    /// real data. The app always talks to the web app over `/api`, never to the database:
    /// the domain logic, the Clerk session and the athlete scoping all live server-side,
    /// and a client holding database credentials would have none of them.
    private static let originVariable = "SHARPIT_API_ORIGIN"

    private static let localDevelopmentOrigin = URL(string: "http://127.0.0.1:3000")!

    static var baseURL: URL {
        if let configured = ProcessInfo.processInfo.environment[originVariable],
           let url = URL(string: configured.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme != nil {
            return url
        }

        #if DEBUG
        return localDevelopmentOrigin
        #else
        return URL(string: "https://REPLACE_PRODUCTION_ORIGIN")!
        #endif
    }
}

enum ClerkConfiguration {
    /// Publishable key only (pk_*). Never place a secret key (sk_*) in the app.
    static let publishableKey = "pk_test_c2FjcmVkLW1vc3F1aXRvLTY1LmNsZXJrLmFjY291bnRzLmRldiQ"
}

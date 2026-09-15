import Foundation

enum APIConfiguration {
    static var baseURL: URL {
        #if DEBUG
        URL(string: "http://127.0.0.1:3000")!
        #else
        URL(string: "https://REPLACE_PRODUCTION_ORIGIN")!
        #endif
    }
}

enum ClerkConfiguration {
    /// Publishable key only (pk_*). Never place a secret key (sk_*) in the app.
    static let publishableKey = "pk_test_c2FjcmVkLW1vc3F1aXRvLTY1LmNsZXJrLmFjY291bnRzLmRldiQ"
}

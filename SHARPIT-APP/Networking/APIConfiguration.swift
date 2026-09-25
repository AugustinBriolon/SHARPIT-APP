import Foundation

enum APIConfiguration {
    /// Environment variable read at launch, so the origin can be switched from the Xcode
    /// scheme (Run → Arguments → Environment Variables) without editing or rebuilding.
    ///
    /// It only exists when Xcode launches the app. A build opened from the home screen or
    /// from TestFlight has no such variable, which is why the build carries its own origin.
    private nonisolated static let originVariable = "SHARPIT_API_ORIGIN"

    /// The origin baked into the build: `SHARPIT_API_ORIGIN` from `Config/*.xcconfig`,
    /// copied into the Info.plist so it travels with the binary.
    private nonisolated static let bundleKey = "SharpitAPIOrigin"

    /// Where the app reaches the web app.
    ///
    /// Point it at a deployed instance — a Vercel preview, or production — when you do
    /// not want the local chain of Docker → Postgres → `yarn dev` running just to see
    /// real data. The app always talks to the web app over `/api`, never to the database:
    /// the domain logic, the Clerk session and the athlete scoping all live server-side,
    /// and a client holding database credentials would have none of them.
    nonisolated static var baseURL: URL {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: bundleKey) as? String
        guard let url = resolve(
            environment: ProcessInfo.processInfo.environment,
            bundleValue: bundleValue
        ) else {
            preconditionFailure("\(bundleKey) is missing or invalid in Info.plist — check Config/*.xcconfig")
        }
        return url
    }

    /// Where the app opens web pages (the published terms and privacy policy): the apex, not
    /// the API origin. Once the API moves to `api.sharpit.app`, that host serves JSON only and
    /// answers every page with a 404, so pages must never be built from `baseURL`.
    nonisolated static var webOrigin: URL {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: webBundleKey) as? String
        guard let url = webOrigin(bundleValue: bundleValue) else {
            preconditionFailure("\(webBundleKey) is missing or invalid in Info.plist — check Config/*.xcconfig")
        }
        return url
    }

    /// `SHARPIT_WEB_ORIGIN` from `Config/*.xcconfig`, copied into the Info.plist.
    private nonisolated static let webBundleKey = "SharpitWebOrigin"

    nonisolated static func webOrigin(bundleValue: String?) -> URL? {
        bundleValue.flatMap(origin(from:))
    }

    /// The scheme override wins, then the build's own origin. A value that is not a usable
    /// origin is skipped rather than trusted, so a typo in the scheme falls back to the
    /// build instead of aiming every request at nothing.
    nonisolated static func resolve(environment: [String: String], bundleValue: String?) -> URL? {
        [environment[originVariable], bundleValue]
            .compactMap { $0 }
            .lazy
            .compactMap(origin(from:))
            .first
    }

    private nonisolated static func origin(from raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme != nil,
              url.host() != nil
        else { return nil }
        return url
    }
}

enum ClerkConfiguration {
    /// Publishable key only (pk_*). Never place a secret key (sk_*) in the app.
    static let publishableKey = "pk_live_Y2xlcmsuc2hhcnBpdC5hcHAk"
}

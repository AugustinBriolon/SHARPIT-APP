import Foundation

/// Closes the first-login wizard server-side.
nonisolated protocol OnboardingServing: Sendable {
    /// Stamps `onboardingCompletedAt` on the athlete's profile, as the web's Finaliser does.
    func completeOnboarding(token: String) async throws
}

/// `/api/v1/onboarding/complete` — the native contract for the web's handler (ADR-040).
actor OnboardingClient: OnboardingServing {
    private let session: URLSession
    private let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = APIConfiguration.baseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func completeOnboarding(token: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/onboarding/complete"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw SharpitAPIError.transport
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 { throw SharpitAPIError.unauthorized }
            throw SharpitAPIError.server
        }
    }
}

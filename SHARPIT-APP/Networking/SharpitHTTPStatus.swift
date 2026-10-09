import Foundation

/// Shared HTTP status → `SharpitAPIError` mapping for authenticated reads that treat
/// 401 and 403 the same (session gone or forbidden for this athlete).
nonisolated enum SharpitHTTPStatus {
    /// Throws `.unauthorized` for 401/403; returns otherwise so the caller can map the rest.
    static func throwIfUnauthorized(_ status: Int) throws {
        if status == 401 || status == 403 {
            throw SharpitAPIError.unauthorized
        }
    }
}

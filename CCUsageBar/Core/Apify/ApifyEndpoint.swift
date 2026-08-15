import Foundation

/// Every URL this app is allowed to request, and the gate that proves it (S1').
///
/// The endpoints are an enum rather than string interpolation at the call site so there is
/// no way to reach the network with an address that did not come from this file, and
/// `validate` is applied to the built URL regardless -- belt and braces, because the value
/// of the allowlist is that it holds even if somebody adds a case carelessly later.
nonisolated enum ApifyEndpoint: Equatable, Sendable {
    case me
    case limits
    case runs(limit: Int)
    case actor(id: String)

    static let scheme = "https"
    static let host = "api.apify.com"
    static let pathPrefix = "/v2/"

    private var path: String {
        switch self {
        case .me: return "/v2/users/me"
        case .limits: return "/v2/users/me/limits"
        case .runs: return "/v2/actor-runs"
        case .actor(let id): return "/v2/acts/\(id)"
        }
    }

    private var queryItems: [URLQueryItem] {
        switch self {
        case .runs(let limit):
            return [
                URLQueryItem(name: "desc", value: "1"),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        case .me, .limits, .actor:
            return []
        }
    }

    /// The request URL, or `nil` if it would not survive `validate`.
    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url, Self.validate(url) else { return nil }
        return url
    }

    /// The allowlist. Anything that is not an unauthenticated `https` request to
    /// `api.apify.com` under `/v2/`, on the default port, is rejected.
    ///
    /// Host is compared for equality, not suffix: `api.apify.com.example.net` is a
    /// different host and must not pass. Userinfo is rejected outright -- this app has no
    /// reason to put credentials in a URL, and they would end up in logs and referrers.
    static func validate(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == Self.scheme else { return false }
        guard let host = url.host?.lowercased(), host == Self.host else { return false }
        guard url.port == nil || url.port == 443 else { return false }
        guard url.user == nil, url.password == nil else { return false }
        // `standardized` collapses any `..` before the prefix is checked.
        return url.standardized.path.hasPrefix(Self.pathPrefix)
    }
}

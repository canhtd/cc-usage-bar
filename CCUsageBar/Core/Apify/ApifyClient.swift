import Foundation

/// The only type in this app that may use `URLSession` (safety invariant S1').
///
/// Every request is a GET to an `ApifyEndpoint`, re-validated against the allowlist before
/// it is sent. The session is ephemeral with cookies and caching off, so nothing about
/// these requests is persisted anywhere on disk. The token is only ever an Authorization
/// header; it is never logged and never put into a URL.
nonisolated final class ApifyClient: Sendable {
    enum ClientError: Error, Equatable, Sendable {
        case noToken
        /// A URL failed the allowlist. Should be unreachable; kept as a hard failure.
        case rejectedURL
        case unauthorized
        case rateLimited
        case http(Int)
        /// The server tried to redirect. Never followed: a 3xx to another host would
        /// re-send the Authorization header to whoever the Location points at.
        case redirectBlocked
        /// A request was attempted while the module is switched off.
        case moduleDisabled
        case offline
        case transport(String)
        case decoding(String)

        var message: String {
            switch self {
            case .noToken: return "No Apify token yet. Add one in Settings › Apify."
            case .rejectedURL: return "Refused to contact an address outside api.apify.com."
            case .unauthorized: return "Apify rejected the token. Check it in Settings › Apify."
            case .rateLimited: return "Apify is rate limiting this token. It will retry."
            case .http(let code): return "Apify returned HTTP \(code)."
            case .redirectBlocked: return "Apify tried to redirect the request; refused."
            case .moduleDisabled: return "Turn on \"Monitor Apify usage\" first."
            case .offline: return "Offline."
            case .transport(let reason): return "Could not reach Apify: \(reason)"
            case .decoding: return "Apify sent a response this version cannot read."
            }
        }
    }

    static let timeout: TimeInterval = 15
    static let runPageSize = 25

    private let session: URLSession
    /// Refuses every redirect. Attached per task, so it also covers an injected session.
    private let redirectBlocker = ApifyRedirectBlocker()

    init() {
        session = Self.hardenedSession()
    }

    #if DEBUG
        /// Test-only seam for a `URLProtocol`-backed session. Not compiled into a release
        /// build, so the shipping path can only ever use `hardenedSession()`.
        init(testSession: URLSession) {
            session = testSession
        }
    #endif

    private static func hardenedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.waitsForConnectivity = false
        // Belt and braces with the per-task delegate below.
        configuration.httpShouldUsePipelining = false
        return URLSession(configuration: configuration)
    }

    // MARK: - Endpoints

    func user(token: String) async throws -> ApifyUser {
        try await get(.me, token: token, as: ApifyUser.self)
    }

    func limits(token: String) async throws -> ApifyLimits {
        try await get(.limits, token: token, as: ApifyLimits.self)
    }

    func runs(token: String, limit: Int = runPageSize) async throws -> [ApifyRun] {
        try await get(.runs(limit: limit), token: token, as: ApifyRunPage.self).items
    }

    func actor(token: String, id: String) async throws -> ApifyActor {
        try await get(.actor(id: id), token: token, as: ApifyActor.self)
    }

    // MARK: - Transport

    private func get<Payload: Decodable & Sendable>(
        _ endpoint: ApifyEndpoint, token: String, as: Payload.Type
    ) async throws -> Payload {
        guard !token.isEmpty else { throw ClientError.noToken }
        guard let url = endpoint.url, ApifyEndpoint.validate(url) else {
            throw ClientError.rejectedURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Self.timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: redirectBlocker)
        } catch let error as URLError {
            throw error.code == .notConnectedToInternet || error.code == .networkConnectionLost
                ? ClientError.offline : ClientError.transport(error.localizedDescription)
        } catch {
            throw ClientError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.transport("the response was not HTTP")
        }
        switch http.statusCode {
        case 200..<300: break
        // A refused redirect completes the task with the 3xx itself; so does a server
        // that sends one without a usable Location. Either way there is no payload.
        case 300..<400: throw ClientError.redirectBlocked
        case 401, 403: throw ClientError.unauthorized
        case 429: throw ClientError.rateLimited
        default: throw ClientError.http(http.statusCode)
        }
        // The URL that actually answered, re-checked against the allowlist: a redirect the
        // loading system resolved below us must not reach the decoder.
        guard let finalURL = http.url, ApifyEndpoint.validate(finalURL) else {
            throw ClientError.rejectedURL
        }

        do {
            return try Self.decoder.decode(ApifyEnvelope<Payload>.self, from: data).data
        } catch {
            throw ClientError.decoding(String(describing: error))
        }
    }

    /// Apify sends ISO-8601 with milliseconds; the built-in `.iso8601` strategy rejects
    /// the fractional part, so both spellings are accepted.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ApifyDateFormats.parse(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "unparseable date: \(text)")
            }
            return date
        }
        return decoder
    }()
}

/// Refuses every HTTP redirect (safety invariant S1').
///
/// `URLSession` follows 3xx responses by default, and it re-sends the request headers to
/// wherever `Location` points. That would hand the Apify bearer token to any host a
/// compromised or misconfigured server named -- the allowlist on the outgoing URL would
/// have been checked, and then quietly bypassed. Returning `nil` here ends the task at the
/// redirect response instead, which `ApifyClient` maps to `ClientError.redirectBlocked`.
///
/// Attached per task rather than as a session delegate, so it also covers the session a
/// test injects.
nonisolated final class ApifyRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

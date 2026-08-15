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
            case .offline: return "Offline."
            case .transport(let reason): return "Could not reach Apify: \(reason)"
            case .decoding: return "Apify sent a response this version cannot read."
            }
        }
    }

    static let timeout: TimeInterval = 15
    static let runPageSize = 25

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = Self.timeout
        configuration.timeoutIntervalForResource = Self.timeout
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
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
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw error.code == .notConnectedToInternet || error.code == .networkConnectionLost
                ? ClientError.offline : ClientError.transport(error.localizedDescription)
        } catch {
            throw ClientError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200..<300: break
            case 401, 403: throw ClientError.unauthorized
            case 429: throw ClientError.rateLimited
            default: throw ClientError.http(http.statusCode)
            }
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

/// ISO-8601 parsing for Apify timestamps.
///
/// `ISO8601DateFormatter` is a reference type and not `Sendable`, so it cannot be held in a
/// shared `static let` under strict concurrency. `Date.ISO8601FormatStyle` is a value type
/// and covers both spellings Apify uses; the formatter is only built, locally, for the
/// unlikely case of a numeric UTC offset in place of `Z`.
nonisolated enum ApifyDateFormats {
    static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    static let plain = Date.ISO8601FormatStyle()

    static func parse(_ text: String) -> Date? {
        if let date = try? fractional.parse(text) { return date }
        if let date = try? plain.parse(text) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

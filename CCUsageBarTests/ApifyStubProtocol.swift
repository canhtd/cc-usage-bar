import Foundation

@testable import CCUsageBar

/// A `URLProtocol` that answers Apify requests from a queue, so the client can be tested
/// without a network and, more importantly, so it can be *proved* not to make requests.
///
/// State is keyed by a channel header rather than held statically. Swift Testing runs tests
/// concurrently, and a single shared queue meant one test consumed another's canned reply
/// and both then saw a fallback error -- the failures looked like client bugs and were not.
/// Each `makeClient()` gets its own channel, so the suites cannot interfere.
nonisolated final class ApifyStubProtocol: URLProtocol {
    static let channelHeader = "X-CCUsageBar-Test-Channel"

    struct Reply: Sendable {
        var statusCode: Int = 200
        var body: Data = Data()
        var headers: [String: String] = ["Content-Type": "application/json"]
        /// When set, the protocol reports an HTTP redirect to this URL, which is what the
        /// redirect blocker has to refuse.
        var redirectTo: URL?

        static func json(_ text: String, status: Int = 200) -> Reply {
            Reply(statusCode: status, body: Data(text.utf8))
        }
    }

    /// One test's queue of canned replies and the URLs it actually saw.
    nonisolated final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [Reply] = []
        private var requested: [URL] = []

        func enqueue(_ reply: Reply) {
            lock.lock()
            defer { lock.unlock() }
            replies.append(reply)
        }

        func nextReply() -> Reply {
            lock.lock()
            defer { lock.unlock() }
            guard !replies.isEmpty else { return Reply(statusCode: 599) }
            return replies.removeFirst()
        }

        func record(_ url: URL?) {
            guard let url else { return }
            lock.lock()
            defer { lock.unlock() }
            requested.append(url)
        }

        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return requested
        }

        var count: Int { urls.count }
        var hosts: [String] { urls.compactMap(\.host) }
    }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var channels: [String: Recorder] = [:]

        func make() -> (String, Recorder) {
            let channel = UUID().uuidString
            let recorder = Recorder()
            lock.lock()
            channels[channel] = recorder
            lock.unlock()
            return (channel, recorder)
        }

        func recorder(for channel: String?) -> Recorder? {
            guard let channel else { return nil }
            lock.lock()
            defer { lock.unlock() }
            return channels[channel]
        }
    }

    private static let registry = Registry()

    /// A client wired to this protocol, with its own recorder. The 5-second timeout means
    /// a stub that never completes fails the test rather than hanging the run.
    static func makeClient() -> (client: ApifyClient, recorder: Recorder) {
        let (channel, recorder) = registry.make()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ApifyStubProtocol.self]
        configuration.httpAdditionalHeaders = [channelHeader: channel]
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        return (ApifyClient(testSession: URLSession(configuration: configuration)), recorder)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorder = Self.registry.recorder(
            for: request.value(forHTTPHeaderField: Self.channelHeader))
        recorder?.record(request.url)
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let reply = recorder?.nextReply() ?? Reply(statusCode: 598)

        if let target = reply.redirectTo {
            let status = reply.statusCode == 200 ? 302 : reply.statusCode
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1",
                headerFields: ["Location": target.absoluteString])!
            var followUp = URLRequest(url: target)
            followUp.httpMethod = request.httpMethod
            // The loading system asks the task delegate what to do; the blocker says no,
            // and the task finishes on this response.
            client?.urlProtocol(self, wasRedirectedTo: followUp, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let response = HTTPURLResponse(
            url: url, statusCode: reply.statusCode, httpVersion: "HTTP/1.1",
            headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

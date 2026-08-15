import Foundation
import Testing

@testable import CCUsageBar

/// Transport behaviour of `ApifyClient`, exercised through a `URLProtocol` stub.
@Suite("Apify client transport")
struct ApifyClientTests {
    private let token = "test-token-not-a-real-credential"

    private func clientError(_ error: any Error) -> ApifyClient.ClientError? {
        error as? ApifyClient.ClientError
    }

    // MARK: - B-1 redirects

    @Test("a 302 to another host is refused, surfaces an error, and is never requested")
    func redirectIsNotFollowed() async throws {
        let (client, recorder) = ApifyStubProtocol.makeClient()
        let elsewhere = try #require(URL(string: "https://evil.example.com/v2/users/me/limits"))
        recorder.enqueue(.init(redirectTo: elsewhere))
        // Would be served if the redirect were followed. It must stay untouched.
        recorder.enqueue(
            .json(#"{"data":{"username":"stolen"}}"#))

        await #expect(throws: (any Error).self) {
            _ = try await client.limits(token: token)
        }
        let hosts = recorder.hosts
        #expect(hosts == ["api.apify.com"], "requested: \(hosts)")
        #expect(hosts.contains("evil.example.com") == false)
    }

    @Test("a redirect to another path on the same host is refused too")
    func sameHostRedirectIsNotFollowed() async throws {
        let (client, recorder) = ApifyStubProtocol.makeClient()
        let target = try #require(URL(string: "https://api.apify.com/v2/users/me"))
        recorder.enqueue(.init(statusCode: 307, redirectTo: target))

        do {
            _ = try await client.limits(token: token)
            Issue.record("expected the redirect to fail the request")
        } catch {
            #expect(clientError(error) == .redirectBlocked)
        }
        #expect(recorder.count == 1)
    }

    // MARK: - Status mapping

    @Test(
        "HTTP statuses map onto the errors the UI explains",
        arguments: [
            (401, ApifyClient.ClientError.unauthorized),
            (403, ApifyClient.ClientError.unauthorized),
            (429, ApifyClient.ClientError.rateLimited),
            (500, ApifyClient.ClientError.http(500)),
            (418, ApifyClient.ClientError.http(418)),
            (301, ApifyClient.ClientError.redirectBlocked),
        ])
    func statusMapping(_ status: Int, _ expected: ApifyClient.ClientError) async throws {
        let (client, recorder) = ApifyStubProtocol.makeClient()
        recorder.enqueue(.json("{}", status: status))
        do {
            _ = try await client.user(token: token)
            Issue.record("expected HTTP \(status) to throw")
        } catch {
            #expect(clientError(error) == expected)
        }
    }

    @Test("an empty token never reaches the network")
    func emptyTokenIsRejectedLocally() async {
        let (client, recorder) = ApifyStubProtocol.makeClient()
        do {
            _ = try await client.user(token: "")
            Issue.record("expected an empty token to throw")
        } catch {
            #expect(clientError(error) == .noToken)
        }
        #expect(recorder.count == 0)
    }

    @Test("a well-formed response decodes, and unreadable JSON is a decoding error")
    func decoding() async throws {
        let (client, recorder) = ApifyStubProtocol.makeClient()
        recorder.enqueue(.json(#"{"data":{"username":"danny"}}"#))
        #expect(try await client.user(token: token).username == "danny")

        recorder.enqueue(.json(#"{"data":{"nope":1}}"#))
        do {
            _ = try await client.user(token: token)
            Issue.record("expected a decoding failure")
        } catch {
            guard case .decoding = clientError(error) else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
        }
    }

    @Test("the bearer token travels in the header, never in the URL")
    func tokenIsNotInTheURL() async throws {
        let (client, recorder) = ApifyStubProtocol.makeClient()
        recorder.enqueue(.json(#"{"data":{"username":"danny"}}"#))
        _ = try await client.user(token: token)
        for url in recorder.urls {
            #expect(url.absoluteString.contains(token) == false)
        }
    }
}

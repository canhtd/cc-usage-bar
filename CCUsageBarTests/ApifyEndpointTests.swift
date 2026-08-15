import Foundation
import Testing

@testable import CCUsageBar

/// The host allowlist that safety invariant S1' rests on.
@Suite("Apify endpoint allowlist")
struct ApifyEndpointTests {
    @Test("every endpoint builds a URL under https://api.apify.com/v2/")
    func endpointsAreAllowed() throws {
        let endpoints: [ApifyEndpoint] = [
            .me, .limits, .runs(limit: 25), .actor(id: "abc123"),
        ]
        for endpoint in endpoints {
            let url = try #require(endpoint.url, "\(endpoint) produced no URL")
            #expect(ApifyEndpoint.validate(url))
            #expect(url.absoluteString.hasPrefix("https://api.apify.com/v2/"))
        }
    }

    @Test("the runs endpoint asks for a descending page of the requested size")
    func runsQuery() throws {
        let url = try #require(ApifyEndpoint.runs(limit: 7).url)
        #expect(url.path == "/v2/actor-runs")
        let query = try #require(url.query())
        #expect(query.contains("desc=1"))
        #expect(query.contains("limit=7"))
    }

    @Test(
        "anything that is not api.apify.com over https is rejected",
        arguments: [
            // Wrong host, including a lookalike that a suffix check would let through.
            "https://evil.example.com/v2/users/me",
            "https://api.apify.com.evil.example.net/v2/users/me",
            "https://apify.com/v2/users/me",
            // Wrong scheme.
            "http://api.apify.com/v2/users/me",
            "ftp://api.apify.com/v2/users/me",
            "file:///etc/passwd",
            // Credentials in the URL.
            "https://user:secret@api.apify.com/v2/users/me",
            // Outside the /v2/ prefix, including an escape via `..`.
            "https://api.apify.com/v1/users/me",
            "https://api.apify.com/",
            "https://api.apify.com/v2/../v1/users/me",
            // Non-default port.
            "https://api.apify.com:8080/v2/users/me",
        ])
    func rejectsForeignURLs(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(ApifyEndpoint.validate(url) == false, "should have rejected \(text)")
    }

    @Test("the host comparison is case-insensitive rather than accidentally strict")
    func acceptsUppercasedHost() throws {
        let url = try #require(URL(string: "HTTPS://API.APIFY.COM/v2/users/me"))
        #expect(ApifyEndpoint.validate(url))
    }

    @Test("only console.apify.com links may be opened from a notification")
    func notificationURLAllowlist() throws {
        let allowed = try #require(URL(string: "https://console.apify.com/actors/runs/abc"))
        #expect(NotificationRouter.isOpenable(allowed))
        for text in [
            "https://evil.example.com/actors/runs/abc",
            "http://console.apify.com/actors/runs/abc",
            "file:///Applications/Calculator.app",
            "https://user:pw@console.apify.com/actors/runs/abc",
        ] {
            let url = try #require(URL(string: text))
            #expect(NotificationRouter.isOpenable(url) == false, "should have rejected \(text)")
        }
    }

    @Test("a run summary links to its own console page")
    func consoleURL() throws {
        let run = ApifyRunSummary(
            id: "abc123", actorName: "Crawler", status: "RUNNING", costUsd: 1, startedAt: nil)
        let url = try #require(run.consoleURL)
        #expect(url.absoluteString == "https://console.apify.com/actors/runs/abc123")
        #expect(NotificationRouter.isOpenable(url))
    }
}

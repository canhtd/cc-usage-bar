import Foundation
import Security
import Testing

@testable import CCUsageBar

/// S2': the token store round-trips one item and touches nothing else.
///
/// Every test uses a throwaway service name and deletes the item it created, so a test run
/// never leaves anything in the user's keychain and never reads the real token.
@Suite("Apify token store")
struct ApifyTokenStoreTests {
    /// Runs `body` against a throwaway store and clears the item afterwards however the
    /// test ends. A helper rather than `defer`, which cannot `await`.
    private func withThrowawayStore(
        _ body: (ApifyTokenStore) async throws -> Void
    ) async throws {
        let store = ApifyTokenStore(
            service: "com.danny.ccusagebar.apify.test.\(UUID().uuidString)")
        do {
            try await body(store)
        } catch {
            try? await store.delete()
            throw error
        }
        try await store.delete()
    }

    @Test("A token round-trips through the keychain and can be deleted")
    func roundTrip() async throws {
        try await withThrowawayStore { store in
            #expect(try await store.read() == nil)
            try await store.save("apify_api_TESTVALUE")
            #expect(try await store.read() == "apify_api_TESTVALUE")

            // Saving again updates in place rather than adding a second item.
            try await store.save("apify_api_SECOND")
            #expect(try await store.read() == "apify_api_SECOND")

            try await store.delete()
            #expect(try await store.read() == nil)
        }
    }

    @Test("Saving an empty string clears the item")
    func emptyClears() async throws {
        try await withThrowawayStore { store in
            try await store.save("something")
            try await store.save("   ")
            #expect(try await store.read() == nil)
        }
    }

    @Test("Deleting a token that is not there is not an error")
    func deleteIsIdempotent() async throws {
        try await withThrowawayStore { store in
            try await store.delete()
            try await store.delete()
        }
    }

    /// The item is pinned to its own service, so one store can never see another's token.
    @Test("Stores with different services cannot see each other's item")
    func storesAreIsolated() async throws {
        try await withThrowawayStore { first in
            try await withThrowawayStore { second in
                try await first.save("first-token")
                #expect(try await second.read() == nil)
                #expect(try await first.read() == "first-token")
            }
        }
    }
}

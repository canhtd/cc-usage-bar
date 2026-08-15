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
    private func throwawayStore() -> ApifyTokenStore {
        ApifyTokenStore(service: "com.danny.ccusagebar.apify.test.\(UUID().uuidString)")
    }

    @Test("A token round-trips through the keychain and can be deleted")
    func roundTrip() throws {
        let store = throwawayStore()
        defer { try? store.delete() }

        #expect(try store.read() == nil)
        try store.save("apify_api_TESTVALUE")
        #expect(try store.read() == "apify_api_TESTVALUE")

        // Saving again updates in place rather than adding a second item.
        try store.save("apify_api_SECOND")
        #expect(try store.read() == "apify_api_SECOND")

        try store.delete()
        #expect(try store.read() == nil)
    }

    @Test("Saving an empty string clears the item")
    func emptyClears() throws {
        let store = throwawayStore()
        defer { try? store.delete() }
        try store.save("something")
        try store.save("   ")
        #expect(try store.read() == nil)
    }

    @Test("Deleting a token that is not there is not an error")
    func deleteIsIdempotent() throws {
        let store = throwawayStore()
        try store.delete()
        try store.delete()
    }

    /// The item is pinned to its own service, so one store can never see another's token.
    @Test("Stores with different services cannot see each other's item")
    func storesAreIsolated() throws {
        let first = throwawayStore()
        let second = throwawayStore()
        defer {
            try? first.delete()
            try? second.delete()
        }
        try first.save("first-token")
        #expect(try second.read() == nil)
        #expect(try first.read() == "first-token")
    }
}

import Foundation
import Security

/// The seam the runtime talks to, so a test can substitute a store that never opens the
/// keychain -- including one that deliberately never answers, which is what proves a
/// pending keychain dialog no longer stalls the rest of the app.
///
/// Every operation is `async`: see `KeychainQueue` for why none of them may run inline.
protocol ApifyTokenStoring: Sendable {
    func read() async throws -> String?
    func save(_ token: String) async throws
    func delete() async throws
}

/// Runs every Security.framework call off the main actor, one at a time.
///
/// `SecItemCopyMatching` blocks its thread, and it can block for a very long time: an
/// ad-hoc signed build asks "CCUsageBar wants to use your confidential information" on the
/// first read after every reinstall, and the call does not return until the user answers.
/// Called inline on the main actor that froze the whole app -- menu bar, popover, the
/// Claude refresh and its timeout with it (observed: a six-minute hang).
///
/// A dedicated serial queue rather than an actor on purpose: a blocked cooperative-pool
/// thread is a thread Swift concurrency cannot use for anything else, and this one is
/// expected to block for as long as a human takes to answer a dialog.
private enum KeychainQueue {
    private static let queue = DispatchQueue(label: "com.danny.ccusagebar.keychain")

    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
}

/// The only type in this app that touches Security.framework (safety invariant S2').
///
/// It reads and writes exactly one generic-password item, pinned to this app's own service
/// and a single fixed account. Every query carries both attributes, so there is no code
/// path here that can enumerate, match or return anybody else's keychain item -- not the
/// user's Claude credentials, not another app's token.
///
/// The token is never logged, never written to Application Support, never put in history
/// and never shown in the raw-output view. It leaves this type only as an Authorization
/// header inside `ApifyClient`.
nonisolated struct ApifyTokenStore: ApifyTokenStoring {
    /// Service attribute of the app's own item.
    static let defaultService = "com.danny.ccusagebar.apify"
    /// One token for the app, independent of Claude profiles (A1).
    static let account = "apify-api-token"

    enum StoreError: Error, Equatable {
        /// The keychain refused the operation; carries the raw `OSStatus` for diagnosis.
        case keychain(OSStatus)
        /// The item exists but does not hold UTF-8 text. Surfaced rather than swallowed:
        /// silently reporting "no token" would send the user to re-enter a token that is
        /// already there, and would keep doing so.
        case invalidData
    }

    let service: String

    init(service: String = defaultService) {
        self.service = service
    }

    /// Attributes identifying this app's single item. Deliberately the whole identity:
    /// class, service and account are always all present.
    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    /// The stored token, or `nil` when the user has not set one.
    func read() async throws -> String? {
        try await KeychainQueue.run { try readItem() }
    }

    private func readItem() throws -> String? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = item as? Data else { throw StoreError.invalidData }
        guard let token = String(data: data, encoding: .utf8) else {
            throw StoreError.invalidData
        }
        return token
    }

    /// Replaces the stored token. An empty string clears it.
    func save(_ token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return try await delete() }
        try await KeychainQueue.run { try writeItem(Data(trimmed.utf8)) }
    }

    private func writeItem(_ data: Data) throws {
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw StoreError.keychain(updateStatus) }

        var insert = identity
        insert[kSecValueData as String] = data
        // Available whenever the user is logged in; the app refreshes on a timer and must
        // not need an unlock prompt to do it.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        insert[kSecAttrDescription as String] = "Apify API token for CC Usage Bar"
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
    }

    #if DEBUG
        /// Test-only: writes raw bytes, so the "item exists but is not text" path can be
        /// exercised. Never compiled into a release build.
        func saveRawForTesting(_ data: Data) async throws {
            try await delete()
            try await KeychainQueue.run {
                var insert = identity
                insert[kSecValueData as String] = data
                insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                let status = SecItemAdd(insert as CFDictionary, nil)
                guard status == errSecSuccess else { throw StoreError.keychain(status) }
            }
        }
    #endif

    func delete() async throws {
        try await KeychainQueue.run {
            let status = SecItemDelete(identity as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw StoreError.keychain(status)
            }
        }
    }
}

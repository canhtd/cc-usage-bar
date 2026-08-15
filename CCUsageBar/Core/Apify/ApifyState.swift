import Foundation
import Security

/// What the Apify module is currently doing, as the UI needs to describe it.
nonisolated enum ApifyState: Equatable, Sendable {
    case disabled
    case needsToken
    /// The keychain could not be read. Distinct from `needsToken` on purpose: the fix is
    /// not "enter a token", and the module should keep retrying.
    case keychainUnavailable(OSStatus)
    case loading
    case ready
    case failed(ApifyClient.ClientError)

    var isLoading: Bool { self == .loading }

    var message: String? {
        switch self {
        case .disabled, .ready: return nil
        case .needsToken: return ApifyClient.ClientError.noToken.message
        case .keychainUnavailable(let status):
            return "Keychain unavailable (\(status)) — will retry."
        case .loading: return "Loading Apify usage…"
        case .failed(let error): return error.message
        }
    }

    /// Whether the message should send the user to Settings rather than just inform them.
    var needsSettings: Bool {
        switch self {
        case .needsToken: return true
        case .failed(let error): return error == .unauthorized
        default: return false
        }
    }
}

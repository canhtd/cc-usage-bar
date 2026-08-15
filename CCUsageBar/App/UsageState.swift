import Foundation

/// What the UI should say about one profile right now.
nonisolated enum UsageState: Equatable, Sendable {
    /// No fetch has completed yet in this launch.
    case never
    case loading
    case ready
    /// Data is present, but Claude Code says a limit has been reached.
    case rateLimited
    /// Claude Code has not been set up on this machine for this profile.
    case needsSetup
    case error(UsageSessionError)

    var isLoading: Bool { self == .loading }

    /// True when there is nothing trustworthy to show in the menu bar.
    var isUnknown: Bool {
        switch self {
        case .ready, .rateLimited: return false
        default: return true
        }
    }

    var message: String? {
        switch self {
        case .never: return "No data yet."
        case .loading: return "Reading /usage…"
        case .ready: return nil
        case .rateLimited: return "A usage limit has been reached."
        case .needsSetup: return UsageSessionError.needsSetup.message
        case .error(let error): return error.message
        }
    }

    /// SF Symbol shown next to the message in the popover footer.
    var symbolName: String? {
        switch self {
        case .never: return "questionmark.circle"
        case .loading: return nil
        case .ready: return nil
        case .rateLimited: return "exclamationmark.octagon"
        case .needsSetup: return "person.crop.circle.badge.exclamationmark"
        case .error: return "exclamationmark.triangle"
        }
    }
}

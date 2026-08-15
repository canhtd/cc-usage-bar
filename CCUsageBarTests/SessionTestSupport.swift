import Foundation
import Testing

/// Screens and waiting helpers shared by the session test suites.
enum SessionScreens {
    /// A screen with the prompt caret, which is what tells the session it may type.
    static let ready = "Welcome back\r\n\u{276F} \r\n? for shortcuts\r\n"
    static let panel = """
        Current session\r
        \u{2588}\u{2588}\u{2588}  48% used\r
        Resets 1:09pm (Asia/Saigon)\r

        """
}

/// Waits for `condition`, so tests do not depend on how fast the machine is.
@MainActor
func untilTrue(
    _ condition: () -> Bool, timeout: Duration = .seconds(15)
) async -> Bool {
    let deadline = Date().addingTimeInterval(TimeInterval(timeout.components.seconds))
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return condition()
}

import Foundation
import Testing

@testable import CCUsageBar

/// R4: the state machine's decisions are string matches, so they are tested directly.
@Suite("Screen signals")
struct ScreenSignalsTests {
    @Test("The prompt caret means the CLI is ready for input")
    func promptReady() {
        #expect(ScreenSignals.isPromptReady("│ \u{276F} \n ? for shortcuts"))
        #expect(ScreenSignals.isPromptReady("⏵⏵ bypass permissions on (shift+tab to cycle)"))
        #expect(!ScreenSignals.isPromptReady("Loading…"))
    }

    @Test("The trust dialog is recognised")
    func trustPrompt() {
        #expect(ScreenSignals.isTrustPrompt("Do you trust the files in this folder?"))
        #expect(ScreenSignals.isTrustPrompt("Quick safety check"))
        #expect(!ScreenSignals.isTrustPrompt("Current session"))
    }

    @Test("Onboarding and login screens map to needs-setup")
    func needsSetup() {
        #expect(ScreenSignals.needsSetup("Select login method"))
        #expect(ScreenSignals.needsSetup("Choose the text style that looks best"))
        #expect(ScreenSignals.needsSetup("Invalid API key · Please run /login"))
        #expect(!ScreenSignals.needsSetup("Welcome back Sample!"))
    }

    /// Regression: the launch splash of a healthy, logged-in session used to be read as
    /// onboarding because it contains "Let's get started", which made the menu bar show
    /// "needs setup" at random on a cold session start.
    @Test("The ordinary launch splash is not mistaken for onboarding")
    func launchSplashIsNotSetup() {
        let splash = """
            Welcome to Claude Code v2.1.233

                 *                                       \u{2588}\u{2588}\u{2593}\u{2591}
                        \u{2591}\u{2591}\u{2591}\u{2591}\u{2591}\u{2591}

             Let's get started
            """
        #expect(!ScreenSignals.needsSetup(splash))
        #expect(!ScreenSignals.needsSetup("Tips for getting started"))
        // The real onboarding screens are still detected.
        #expect(ScreenSignals.needsSetup("Let's get started\nChoose the text style"))
    }

    @Test("A missing executable is recognised from the shell's own message")
    func commandNotFound() {
        #expect(ScreenSignals.isCommandNotFound("zsh:1: command not found: claude"))
        #expect(!ScreenSignals.isCommandNotFound("Current session"))
    }

    @Test("The usage panel is detected only once a bar has painted")
    func usagePanel() {
        #expect(ScreenSignals.hasUsagePanel("████  48% used"))
        #expect(ScreenSignals.hasUsagePanel("0% used"))
        #expect(!ScreenSignals.hasUsagePanel("Context 0% | 5h: 48% (2h3m)"))
        #expect(!ScreenSignals.hasUsagePanel("100% of your usage came from subagents"))
    }

    @Test("Limit messages set the rate-limited state")
    func rateLimited() {
        #expect(ScreenSignals.isRateLimited("You've reached your usage limit"))
        #expect(!ScreenSignals.isRateLimited("Current week (all models)"))
    }

    @Test("Every session error carries a message a user can act on")
    func errorMessages() {
        let errors: [UsageSessionError] = [
            .needsSetup, .claudeNotFound, .timedOut, .processExited(1),
            .launchFailed("boom"), .noUsageSections,
        ]
        for error in errors {
            #expect(!error.message.isEmpty)
            #expect(error.message.first?.isUppercase == true || error.message.hasPrefix("`"))
        }
    }
}

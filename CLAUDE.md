# CC Usage Bar — project rules

macOS menu-bar app (AppKit shell, SwiftUI views) that reads Claude Code's `/usage` through
a pseudo-terminal. Read `docs/SPEC.md` for the full product spec.

## Safety invariants — check every one before shipping any change

These are the reason this app is trustworthy. A change that breaks one is a bug, however
convenient it seems.

- [ ] **S1' — Network is allowlisted, not forbidden.** Exactly one file,
      `Core/Apify/ApifyClient.swift`, may use `URLSession`/`URLRequest`. Every URL is built
      by `ApifyEndpoint` and re-validated by `ApifyEndpoint.validate` against
      `https://api.apify.com/v2/` on the default port, with no userinfo — proven by
      `ApifyEndpointTests`. Ephemeral session, no cookies, no cache, 15 s timeout. Requests
      happen only while the user has enabled the Apify module. No `NWConnection`, no
      `socket(`, no networking anywhere else in the app target.
      The only other outbound action is `NSWorkspace.open` in `NotificationRouter`, limited
      to `https://console.apify.com/...` by the same kind of check.
- [ ] **S2' — Keychain is app-own only.** Exactly one file,
      `Core/Apify/ApifyTokenStore.swift`, may touch Security.framework. It reads and writes
      one generic-password item, always pinned to both `kSecAttrService`
      (`com.danny.ccusagebar.apify`) and `kSecAttrAccount` (`apify-api-token`), so no query
      here can enumerate or return another item. The token is never logged, never written
      to Application Support, never recorded in history and never shown in the raw view.
- [ ] **S3 — No credential access.** Never read `~/.claude`, `.credentials.json`, or
      anything matching `sk-ant`. The Apify token is typed or pasted by the user into a
      `SecureField`; it is never discovered from disk or the environment. Writes are limited
      to `AppSupport.directory` and the per-session temporary directory from
      `PTYLaunchSpec.makeScratchDirectory()`.
- [ ] **S4 — One subprocess shape.** `/bin/zsh -l -c claude` in a PTY, cwd = fresh empty
      temp dir, env inherited plus `TERM` and optionally `CLAUDE_CONFIG_DIR`. Exactly one
      `execve` call site: `PTYProcess.launch`. The only bytes ever written to the PTY are
      the ones in `PTYInput`: `/usage`, `\r`, and ESC.
- [ ] **S5 — No third-party dependencies.** Apple frameworks only. No SwiftPM packages, no
      vendored binaries.
- [ ] **S6 — No build phases that run scripts.** App sandbox off (needed for `fork`/`exec`),
      hardened runtime on.

Run this before claiming a change is safe:

```sh
# S1': URLSession only in ApifyClient.swift.
grep -rnE 'URLSession|URLRequest|NWConnection|socket\(' CCUsageBar/ \
  | grep -v 'Core/Apify/ApifyClient.swift'
# S2': Security.framework only in ApifyTokenStore.swift.
grep -rnE 'SecItem|kSec' CCUsageBar/ | grep -v 'Core/Apify/ApifyTokenStore.swift'
# S3: no Claude credentials, ever. (`credentials` is left out on purpose -- it is an
# ordinary English word that appears in comments; the two patterns below are not.)
grep -rnE '\.claude/|sk-ant' CCUsageBar/
# Opening a URL only in NotificationRouter, which checks the host first.
grep -rn 'NSWorkspace.shared.open' CCUsageBar/ \
  | grep -v 'Core/Notifications/NotificationRouter.swift'
# S4: one execve call site.
grep -rn 'execve(' CCUsageBar/
# No file over 200 lines.
find CCUsageBar -name '*.swift' -exec wc -l {} + | awk '$1 > 200 && $2 != "total"'
```

Every one of these must print nothing except the single `execve(` line in
`PTYProcess.swift`.

## Code rules

- Swift 6 language mode, strict concurrency complete, default actor isolation `MainActor`.
- **No file over 200 lines.** Split by responsibility; that is why `UsageSession` and
  `UsageSession+Query` are two files.
- English code and comments. Every user-visible string in English.
- Pure logic (parsers, formatters, threshold rules, retention) lives in `nonisolated`
  types with no AppKit import, so it is unit-testable.
- Comments explain *why*, especially where the code looks odd: the differential Ink
  repaint, the CR+LF grapheme, the `nonisolated` dispatch handlers, the pre-fork C arrays.

## Gotchas learned the hard way

- **Do not regex-strip ANSI from the raw stream to get text.** Ink repaints differentially
  (`ESC [ n G` then two characters), so stripping yields corrupted words. Replay the stream
  onto `ANSIScreen` and read the grid back.
- **Do not switch on `Character` for control codes.** Swift folds `\r\n` into one grapheme;
  dispatch on `Unicode.Scalar`.
- **Do not write dispatch source handlers inline in a `@MainActor` type.**
  `setEventHandler` takes a non-`Sendable` block, so the closure inherits main-actor
  isolation and traps when dispatch runs it on a global queue. Build them in `nonisolated`
  helpers (see `PTYProcess.attachReadHandler`).
- **Screen markers must be unique to the state they detect.** `needsSetup` once matched
  "Let's get started", which Claude Code also prints in its ordinary launch splash, so a
  healthy session reported "needs setup" at random. Prefer a marker that cannot appear on
  a logged-in screen, and check a new one against a real cold-start capture.
- **Tests must not read the source tree.** The test host is a signed app, so opening a
  file under `~/Documents` raises the Documents privacy prompt; with nobody to answer it
  the run hangs in `open(2)` at 0% CPU with no error. Load fixtures from the test bundle
  (`FixtureLoader`), which lives in DerivedData.
- **Never decode PTY bytes with a fallback encoding.** A split multi-byte sequence must be
  carried over, not reinterpreted as Latin-1.

## Verification — required before saying "done"

1. `xcodebuild -scheme CCUsageBar -configuration Release build` → BUILD SUCCEEDED, 0 warnings.
2. `xcodebuild test -scheme CCUsageBar` → all tests pass.
3. Safety greps above → no hits.
4. `otool -L` on the built binary → system libraries only (Security and CFNetwork are
   expected since v2.1; anything outside `/usr/lib` and `/System/Library` is not).
5. Launch the built `.app`, confirm the menu bar shows real percentages, open the popover
   and Settings, take a screenshot.
6. Quit, then `pgrep -fl claude` → no child process left behind by the app.

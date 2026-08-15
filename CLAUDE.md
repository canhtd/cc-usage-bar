# CC Usage Bar — project rules

macOS menu-bar app (AppKit shell, SwiftUI views) that reads Claude Code's `/usage` through
a pseudo-terminal. Read `docs/SPEC.md` for the full product spec.

## Safety invariants — check every one before shipping any change

These are the reason this app is trustworthy. A change that breaks one is a bug, however
convenient it seems.

- [ ] **S1 — No network.** No `URLSession`, `URLRequest`, `NWConnection`, `socket(`, or any
      networking API in the app target.
- [ ] **S2 — No Keychain.** No `SecItem*`, no `kSec*`.
- [ ] **S3 — No credential access.** Never read `~/.claude`, `.credentials.json`, or
      anything matching `sk-ant`. Writes are limited to `AppSupport.directory` and the
      per-session temporary directory from `PTYLaunchSpec.makeScratchDirectory()`.
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
grep -rnE 'URLSession|URLRequest|NWConnection|socket\(|SecItem|kSecClass|\.claude/|credentials|sk-ant' CCUsageBar/
grep -rn 'execv' CCUsageBar/
```

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
4. `otool -L` on the built binary → system libraries only.
5. Launch the built `.app`, confirm the menu bar shows real percentages, open the popover
   and Settings, take a screenshot.
6. Quit, then `pgrep -fl claude` → no child process left behind by the app.

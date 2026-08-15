# CC Usage Bar — Product & Technical Spec (v2 rewrite)

Owner: Danny. Status: APPROVED for implementation. Executor decides HOW; this doc fixes WHAT/WHY and hard constraints.

## 0. Origin & licence
Ground-up rewrite inspired by github.com/lionhylra/cc-usage-bar (MIT, Yilei He). Keep MIT; credit original in LICENSE/README ("Inspired by…"). Do NOT copy files verbatim; the original's PTY approach is the reference, its bugs (Latin-1 fallback, empty Settings scene, ANSI scraping) are what we fix.

## 1. Purpose
macOS menu-bar app that shows Claude Code usage (`/usage`) at a glance, always accurate, without touching credentials.

## 2. Non-negotiable safety invariants (audit-grade — reviewer must verify each)
S1. **No network.** Zero URLSession/URLRequest/NWConnection/sockets anywhere in app target.
S2. **No Keychain.** Zero SecItem*/kSec* usage.
S3. **No credential file access.** Never read `~/.claude/*`, `.credentials.json`, anything containing `sk-ant`. The only filesystem writes: app's own Application Support dir + a temp cwd dir.
S4. **Only one subprocess shape:** `/bin/zsh -l -c claude` (login shell so PATH is the user's) inside a PTY, cwd = fresh empty temp dir, env inherits + `TERM=xterm-256color`, optionally `CLAUDE_CONFIG_DIR=<profile dir>` for profiles. Nothing else is ever exec'd. Only these bytes are ever written to the PTY: `/usage`, `\r`, ESC (`\u{1B}`), and `\r` to accept the "Quick safety check" trust prompt.
S5. **Zero third-party dependencies.** Apple frameworks only (AppKit, SwiftUI, Charts, UserNotifications, ServiceManagement, OSLog, Combine). No SwiftPM packages, no binaries in repo.
S6. No build phases running scripts. App sandbox OFF (required for fork/exec), hardened runtime ON.

## 3. Features (all must ship)
F1. **Menu bar item**: SF Symbol + text `47% · 25%` (session · week-all-models). Text color: default ≤69%, orange 70–89%, red ≥90%. Option to show icon only. Grey/dimmed with "—" when unknown/error.
F2. **Popover** (left-click): native SwiftUI, NOT a terminal dump. For each usage section parsed from `/usage`: title, real ProgressView bar with %, "Resets …" text; sections in the order Claude Code prints them. Footer: last-updated relative time, refresh button, state (loading/error/needs-setup/rate-limited) with clear messages + a "Show raw output" disclosure that reveals the ANSI-rendered raw text (debug/fallback). Sparkline of last 24h per section (Swift Charts) beneath the bars.
F3. **Auto-refresh**: interval setting Off/1/5/15/30/60 min (default 5). Manual refresh always available. Refresh also on wake from sleep. Never overlap two fetches for the same profile.
F4. **Notifications** (UserNotifications): thresholds configurable (default 80/95 %); fire once per threshold per reset window per section per profile; setting to enable/disable per section (session/week). Ask permission lazily on first enable.
F5. **Usage history**: append a snapshot (timestamp, profile, section, percent, resetsAt-if-parsable) after each successful fetch to a JSON/JSONL file in `~/Library/Application Support/CCUsageBar/`. Retention 30 days, pruned on launch. History view in Settings: line chart per section over 24h/7d/30d.
F6. **Launch at login**: SMAppService toggle in Settings.
F7. **Profiles**: list of {name, configDir (optional path)}. Default profile "Default" has no configDir (plain `claude`). Profile with configDir sets `CLAUDE_CONFIG_DIR`. Menu bar shows the *active* profile; popover has a profile picker; each profile has its own session/PTY. Settings CRUD (add/rename/remove/pick folder via NSOpenPanel — no free-text typing of secrets, it's just a directory).
F8. **Settings window** (real, ⌘,): tabs General (refresh, menu bar display, launch at login), Notifications, Profiles, History, About (version, licence, "Inspired by").
F9. **Right-click menu**: Refresh now, profile submenu, Settings…, Quit.

## 4. Robustness requirements (the bugs we're fixing)
R1. **UTF-8**: decode PTY bytes with an incremental decoder that carries incomplete trailing multibyte sequences over to the next chunk; never fall back to Latin-1; never decode a truncated buffer as a whole. Unit-tested with `█`, `·`, `—`, `▓░` split at every byte offset.
R2. **ANSI/Ink handling**: keep a virtual-screen ANSI parser (cursor moves, erase, SGR colors) for the raw view; but the *data* path parses text with ANSI stripped, tolerant to Ink re-render duplicates.
R3. **/usage parser** → `UsageSnapshot { sections: [UsageSection(id/title, percentUsed: Int, resetsText: String?, resetsAt: Date?)] }`. Must handle: "Current session", "Current week (all models)", "Current week (<Model>)" (any model name), promo lines (ignore/keep as note), unknown future sections (still show title+%). Parser is pure and unit-tested against fixtures captured from real output (executor captures at least one real fixture from this machine and commits it under Tests/Fixtures — verify it contains no secrets before committing).
R4. **Session state machine** (waitingForBanner → waitingForPrompt → waitingForResult → capturing → idle) with per-query IDs, timeouts (30s), idle-settle (1.5s), SIGWINCH nudge to force full Ink redraw, session reuse between queries, teardown on error; detect first-run/onboarding screens → `needsSetup` with instruction "Run `claude` in Terminal once and log in". Detect `claude` not found (exit 127) → clear message. Kill child + close PTY on quit; no zombie processes (waitpid).
R5. Swift 6 language mode, strict concurrency clean, `@MainActor` view models, no data races on PTY fd.
R6. No file >200 lines; split by responsibility (PTY, decoder, ANSI, parser, session, store, notifier, views, settings).
R7. Every user-visible string in English. Code comments English.

## 5. Project shape
- Path: `~/Documents/Projects/cc-usage-bar/`
- Xcode project `CCUsageBar.xcodeproj` at repo root using Xcode 16+ **folder-synchronized groups** (`PBXFileSystemSynchronizedRootGroup`) so no per-file pbxproj bookkeeping. Reference for the pbxproj shape: re-clone the original repo into the scratchpad and mimic its project.pbxproj (it is one of these). Bundle ID `com.danny.ccusagebar`, LSUIElement=YES, MACOSX_DEPLOYMENT_TARGET 15.0 (Sequoia) — Charts/SMAppService/UNUserNotifications are all fine there. Targets: `CCUsageBar` (app), `CCUsageBarTests` (unit, Swift Testing). Shared scheme committed under xcshareddata so `xcodebuild -scheme CCUsageBar` works.
- Layout: `CCUsageBar/App`, `/Core/PTY`, `/Core/Parsing`, `/Core/Store`, `/Core/Notifications`, `/Features/MenuBar`, `/Features/Popover`, `/Features/Settings`, `/Resources`, `CCUsageBarTests/`, `docs/`.
- `README.md` (what/why/safety model/build), `LICENSE` (MIT + inspiration credit), `CLAUDE.md` (project rules: safety invariants S1–S6 as a checklist for any future change; verification = build + tests + launch + screenshot), `.gitignore` (Xcode/DerivedData/build).
- App icon: simple generated asset (SF-symbol-based or programmatic) is fine; do not copy the original PNGs.

## 6. Done criteria (evidence required in the report)
D1. `xcodebuild -scheme CCUsageBar -configuration Release build` → BUILD SUCCEEDED, 0 warnings.
D2. `xcodebuild test -scheme CCUsageBar` → all tests pass; ≥ tests for UTF-8 decoder splits, /usage parser fixtures, ANSI parser, threshold notifier logic (pure), history pruning.
D3. Safety grep over app sources returns nothing for: `URLSession|URLRequest|NWConnection|socket\(|SecItem|kSecClass|\.claude/|credentials|sk-ant`. Only `execv` call site is the `/bin/zsh -l -c claude` one. `otool -L` on the built binary: system libs only.
D4. App launched from the built .app on this Mac (macOS 26.3): menu bar shows real percentages; popover shows parsed sections with bars (no `â` garbage); screenshot(s) of menu bar item + popover + Settings attached (use `screencapture`). Quitting leaves no `claude` child processes from the app (`pgrep -f` evidence).
D5. Copy the Release .app to `/Applications/CCUsageBar.app` **replacing** the old build (old one was v1.1.1 of the original — quit it first with `pkill -x CCUsageBar` if running).
D6. `git init` + a single initial commit (no AI attribution lines in the message).

---

# Addendum A — Apify usage monitor (v2.1) — APPROVED

## A0. Why
A single Apify session once burned 50% of the monthly budget unnoticed. Danny wants budget %, spike and expensive-run alerts next to the Claude numbers, in the same menu bar item.

## A1. Safety model amendment (supersedes S1–S3 wording; reviewer must re-audit)
S1' **Network is allowlisted, not forbidden.** Exactly one type, `ApifyClient` (one file), may use `URLSession`. It only builds URLs under `https://api.apify.com/v2/`; a unit test proves any other host/scheme is rejected. Ephemeral session config, no cookies, no caching, 15 s timeout. Requests happen only while the Apify module is enabled by the user. Everything else in the app remains network-free (safety grep now excludes only that file).
S2' **Keychain is app-own only.** The Apify token lives in ONE generic-password item owned by this app (service `com.danny.ccusagebar.apify`, account = profile-independent, single). Only `ApifyTokenStore` (one file) touches Security.framework; it never queries other services/accounts. Never log, never write the token anywhere else, never include it in history/raw views.
S3 unchanged: never read `~/.claude`, Claude credentials, or any `sk-ant*`. Apify token is entered by the user in Settings via SecureField (or pasted) — never discovered from disk/env.
S4–S6 unchanged. Update `CLAUDE.md` checklist + safety greps accordingly (grep must whitelist exactly `ApifyClient.swift` for URLSession and `ApifyTokenStore.swift` for SecItem).

## A2. Data (Apify REST v2, Bearer token)
- `GET /v2/users/me/limits` → `current.monthlyUsageUsd`, `limits.maxMonthlyUsageUsd`, `monthlyUsageCycle.startAt/endAt`. Percent = current/max.
- `GET /v2/actor-runs?desc=1&limit=25` → per run: id, actId/actorName (fetch name lazily via `GET /v2/acts/{id}` only when needed and cache), status, startedAt, `usageTotalUsd`. Called whenever the module is enabled, because the popover lists recent runs (A4); the expensive-run rule toggle controls only whether those runs also raise an alert.
- Poll on the same RefreshScheduler cadence as Claude but as an independent task; Apify failure never degrades Claude display and vice-versa.
- Record `monthlyUsageUsd` samples in HistoryStore (source tag `apify`) — drives sparkline + spike rule.

## A3. Alert rules (all pure + unit-tested; delivered via existing NotificationService; each fires once per key)
R-A1 **Budget thresholds**: default 50/80/95 % of `maxMonthlyUsageUsd`; key = `apify|budget|<cycleStartAt>|<threshold>`.
R-A2 **Spike**: usage increase over the trailing 60 min ≥ X % of budget (default 10 %, configurable) → notify "Apify spent $Δ in the last hour (Y % of budget)"; key = `apify|spike|<hour bucket>`. Needs ≥2 samples; tolerant to sparse history.
R-A3 **Expensive run**: any run (running or finished) with `usageTotalUsd ≥ $X` (default $5) → notify "<actor> run cost $Y"; key = `apify|run|<runId>`; notification click opens `https://console.apify.com/actors/runs/<runId>` (only URL the app ever opens, via NSWorkspace).
Settings › Apify tab: enable toggle, token field (masked, "Test connection" button showing account username from `/v2/users/me`), thresholds, spike %, run $ threshold, per-rule enable.

## A4. UI
- Menu bar: append ` · A 52%` when enabled (severity colours: same bands as F1). When Apify errors: ` · A —` in secondary colour.
- Popover: new "Apify" section under the Claude ones: "$X of $Y this month" + percent, ProgressView, "Cycle resets <date> (<n> days)", sparkline (24h/7d selectable like others), then up to 3 most recent runs with cost (name, status, $), and an inline error line (invalid token → "Open Settings" link; offline → "Offline, last updated …"). When module disabled: nothing shown (no nag).
- Settings › History: Apify $ chart alongside Claude sections.

## A5. Done criteria (evidence)
DA1 Build 0 warnings; tests pass (new suites: URL allowlist, response decoding from fixture JSON, budget/spike/run rules, token store round-trip on a throwaway keychain item that the test deletes).
DA2 Safety greps updated in CLAUDE.md pass with the two whitelisted files; `otool -L` may now include Security + CFNetwork only.
DA3 Live: install; Danny enters his token in Settings; "Test connection" shows his username; menu bar shows ` · A nn%`. Executor cannot do this step (no token) — hand it to the CTO with exact instructions.
DA4 Screenshots: settings-apify.png, popover with Apify section (may use a fixture-backed debug flag in Debug build).
DA5 One commit "Add Apify usage monitor" (no AI attribution). Bump CFBundleShortVersionString to 2.1.

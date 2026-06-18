---
task_id: T-MAC-30
adapter: kimi
model: (vendor default)
status: done
pid: 10032
start_time: "2026-06-18T05:29:27.179Z"
end_time: "2026-06-18T05:32:10.814Z"
exit_code: 0
duration_ms: 162635
mode: background
phase: completed
last_progress_at: "2026-06-18T05:32:10.814Z"
last_progress: swift build + swift test passed (41 tests, 0 failures).
progress_seq: 2
progress_log: ./T-MAC-30-progress.log
raw_log: ./T-MAC-30-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: true
session_id: null
log: ./T-MAC-30-output.log
started_by_pid: 10030
---

# T-MAC-30 — Clipboard watcher for macOS

## Summary
Implemented the macOS clipboard watcher per spec §4/§4.1. `ClipboardFilter` (Core) contains the pure, unit-testable pipeline filters: empty/whitespace skip, `maxChars` bound, consecutive-duplicate suppression, self-write guard via stable text hash, and debounce with an injectable clock. `ClipboardWatcher` (App) polls `NSPasteboard.general.changeCount` on a ~250 ms `Timer`, feeds text through the filter, and invokes a callback wired into `TranslationPipeline` in `AppDelegate`. The watcher is started on launch only when `general.listenClipboard` is enabled, and exposes `markSelfWrite(_:)` for future copy-button use.

## Files touched

| Path | Δ lines | Purpose |
|------|---------|---------|
| `platforms/macos/src/Core/ClipboardFilter.swift` | +88 | Pure filter logic (shouldProcess, self-write hash, debounce with injectable clock). |
| `platforms/macos/src/App/ClipboardWatcher.swift` | +66 | NSPasteboard polling timer, filter invocation, listen toggle, markSelfWrite. |
| `platforms/macos/tests/ClipboardFilterTests.swift` | +117 | 19 unit tests covering static filters, hash stability, self-write consumption, debounce boundary. |
| `platforms/macos/src/App/AppDelegate.swift` | +25/-3 | Imports Core, builds pipeline + filter + watcher, starts watcher gated by `listenClipboard`. |

## Acceptance verification (8/8)

- **Core — `ClipboardFilter.swift` exists in Core**
  - ✓ `ls platforms/macos/src/Core/ClipboardFilter.swift`
  - Evidence: file exists, compiled as part of `TranslateTheDamnCore`.

- **Core — `shouldProcess(newText:lastProcessed:maxChars:)` returns false for empty/whitespace, > maxChars, or duplicate**
  - ✓ `swift test --filter ClipboardFilterTests`
  - Evidence: `testShouldProcessRejectsEmptyString`, `testShouldProcessRejectsWhitespaceOnly`, `testShouldProcessRejectsTextOverMaxChars`, `testShouldProcessRejectsDuplicateOfLastProcessed` all passed.

- **Core — self-write guard via `markSelfWrite(text:)` + `isSelfWrite(text:)`**
  - ✓ `swift test --filter ClipboardFilterTests`
  - Evidence: `testMarkedSelfWriteIsRecognized`, `testSelfWriteGuardIsConsumedOnce`, `testUnmarkedTextIsNotSelfWrite` passed; guard uses `ClipboardFilter.hash(_:)`.

- **Core — debounce with injectable clock closure `() -> Date`**
  - ✓ `swift test --filter ClipboardFilterTests`
  - Evidence: `testDebounceIgnoresBurstWithinInterval`, `testDebounceAcceptsAfterInterval`, `testDebounceIntervalIsInclusiveAtBoundary` passed; `ClipboardFilter.init(maxChars:debounceIntervalMs:clock:)` accepts `() -> Date`.

- **App — `ClipboardWatcher.swift` polls `NSPasteboard.general.changeCount` on ~250ms Timer**
  - ✓ `grep -n "Timer.scheduledTimer(withTimeInterval: 0.25" platforms/macos/src/App/ClipboardWatcher.swift`
  - Evidence: line 42 uses `Timer.scheduledTimer(withTimeInterval: interval, repeats: true)` with default `interval = 0.25`.

- **App — reads `string(forType: .string)`, runs through `ClipboardFilter`, invokes `(String) -> Void` callback, honors `listenClipboard` toggle, exposes `markSelfWrite(_:)`**
  - ✓ `grep -n "string(forType: .string)" platforms/macos/src/App/ClipboardWatcher.swift`
  - Evidence: line 55 reads string; lines 50-60 run filter + callback; `start()/stop()` honor toggle; `markSelfWrite(_:)` at line 48 delegates to filter.

- **AppDelegate wires watcher (start on launch, gated by `ConfigService.defaultConfig().general.listenClipboard`)**
  - ✓ `grep -n "clipboardWatcher?.start" platforms/macos/src/App/AppDelegate.swift`
  - Evidence: line 22 starts watcher inside `if config.general.listenClipboard { ... }`.

- **Build + tests green**
  - ✓ `swift build` succeeded; `swift test` executed 41 tests with 0 failures (22 existing + 19 new).

## Decisions / deviations from spec

- **Supersede**: Not implemented in this change. The current `TranslationPipeline` is synchronous and has no in-flight cancellation token; supersede requires async backend integration and is deferred to the backend/pipeline concurrency task.
- **Self-write hash**: Used a deterministic polynomial rolling hash over UTF-8 bytes instead of a cryptographic hash to avoid external dependencies and keep Core Foundation-only.
- **AppDelegate translator**: Added a private `NoOpTranslator` stub so the pipeline can be wired end-to-end before real backend translators land; it returns the source text unchanged.

## Open questions for Leader

- none

## Commit

`22cc88f` "[T-MAC-30] Implement macOS clipboard watcher with pure filter + polling timer"

## Checks

- `git diff --check` clean (no whitespace errors).
- `swift build` succeeded with only pre-existing Sendable warnings in `PathResolver.swift` and one new Sendable warning in `ClipboardWatcher.swift` (Timer closure capture). No errors.
- `swift test` passed: 41 tests, 0 failures.

## Next recommendation

Cursor is now on T-MAC-30 complete. Next logical tasks are:
- T-MAC-31 (global hotkey service) or
- T-MAC-32 (popup window / SwiftUI overlay).

Both can wire into the existing `AppDelegate` and consume `TranslationPipeline` results.

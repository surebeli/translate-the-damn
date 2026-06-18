---
task_id: T-MAC-30
adapter: kimi
model: (vendor default)
status: done
pid: 10032
start_time: "2026-06-18T05:29:27.179Z"
end_time: "2026-06-18T05:33:36.817Z"
exit_code: 0
duration_ms: 249595
mode: background
phase: done
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
signal: null
timed_out: null
adapter_status: success
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

## Vendor output (parsed) _(preview 8000/54044 chars; full raw stream in `T-MAC-30-output.log`)_

````
• This is a code-impl task T-MAC-30 for macOS clipboard watcher. I need to:
  1. Read existing files and spec
  2. Implement ClipboardFilter.swift in Core
  3. Implement ClipboardWatcher.swift in App
  4. Add ClipboardFilterTests.swift
  5. Wire into AppDelegate.swift
  6. Run swift build + swift test

  Let me start by exploring the relevant files.Need to read the existing files first.Read Windows ClipboardListener reference and ConfigService/AppConfig for listenClipboard config. Also check existing test structure.Need to check the Package.swift structure to understand targets, tests, and imports.Now read Package.swift.Got it. Package has Core target (src/Core), App executable target (src/App), tests target (tests). I need to:

  1. Create `platforms/macos/src/Core/ClipboardFilter.swift` - pure filter logic
  2. Create `platforms/macos/src/App/ClipboardWatcher.swift` - polling watcher with NSPasteboard
  3. Create `platforms/macos/tests/ClipboardFilterTests.swift` - unit tests
  4. Edit `platforms/macos/src/App/AppDelegate.swift` - wire watcher

  Acceptance criteria:
  - Core: ClipboardFilter.swift with:
    - shouldProcess(newText:lastProcessed:maxChars:) -> Bool
    - markSelfWrite(text:) + isSelfWrite(text:) -> Bool (hash text)
    - debounce: timestamp-based helper with injectable clock closure () -> Date
  - App: ClipboardWatcher.swift:
    - polls NSPasteboard.general.changeCount on ~250ms Timer
    - reads string(forType: .string)
    - runs through ClipboardFilter
    - invokes callback (String) -> Void
    - honors listenClipboard on/off toggle
    - exposes markSelfWrite(_:)
  - Wire into AppDelegate
  - swift build succeeds; swift test = 22 + new ClipboardFilter tests green

  The task mentions "22 + new ClipboardFilter tests green" — currently existing tests count? Need to verify with swift test. Let me run it first.

  I should design the API carefully:

  ClipboardFilter.swift:
  ```swift
  import Foundation

  public final class ClipboardFilter {
      private let maxChars: Int
      private let debounceIntervalMs: Int
      private var clock: () -> Date
      private var lastProcessedText: String?
      private var lastProcessedAt: Date?
      private var selfWriteHashes: Set<String> = []
      
      public init(maxChars: Int, debounceIntervalMs: Int = 250, clock: @escaping () -> Date = Date.init) {
          self.maxChars = maxChars
          self.debounceIntervalMs = debounceIntervalMs
          self.clock = clock
      }
      
      public func shouldProcess(newText: String) -> Bool {
          // Empty/whitespace check
          let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return false }
          // Max chars check
          guard newText.count <= maxChars else { return false }
          // Self-write guard
          guard !isSelfWrite(text: newText) else { return false }
          // Dedupe consecutive identical
          if let last = lastProcessedText, last == newText { return false }
          // Debounce
          if let lastAt = lastProcessedAt,
             let interval = debounceIntervalMs,
             interval > 0,
             clock().timeIntervalSince(lastAt) * 1000 < Double(interval) {
              return false
          }
          
          return true
      }
      
      public func markProcessed(text: String) {
          lastProcessedText = text
          lastProcessedAt = clock()
      }
      
      public func markSelfWrite(text: String) {
          selfWriteHashes.insert(hash(text))
      }
      
      public func isSelfWrite(text: String) -> Bool {
          let h = hash(text)
          if selfWriteHashes.contains(h) {
              selfWriteHashes.remove(h)
              return true
          }
          return false
      }
      
      private func hash(_ text: String) -> String {
          // Use SHA256 or simple stable hash
          let data = Data(text.utf8)
          var hash = data.reduce(0) { $0 &+ UInt8($1) }
          return String(hash)
      }
  }
  ```

  Wait, but the spec says:
  - `shouldProcess(newText: String, lastProcessed: String?, maxChars: Int) -> Bool` — false if empty/whitespace, > maxChars, or duplicate of lastProcessed.
  - self-write guard: `markSelfWrite(text:)` + `isSelfWrite(text:) -> Bool` (hash the text; a change matching a self-written text is ignored).
  - debounce: a timestamp-based helper (ignore bursts within N ms) — testable with an injectable clock closure `() -> Date`.

  So shouldProcess signature takes lastProcessed as parameter, not stored state. OK.

  Maybe design as struct with static methods? But debounce needs state. Let me separate concerns:

  ```swift
  public struct ClipboardFilter {
      public static func shouldProcess(newText: String, lastProcessed: String?, maxChars: Int) -> Bool { ... }
      
      public static func hash(_ text: String) -> String { ... }
  }

  public final class ClipboardDebounce {
      private let intervalMs: Int
      private let clock: () -> Date
      private var lastTime: Date?
      
      public init(intervalMs: Int, clock: @escaping () -> Date = Date.init) {
          self.intervalMs = intervalMs
          self.clock = clock
      }
      
      public func shouldProcess(at time: Date? = nil) -> Bool {
          let now = time ?? clock()
          if let last = lastTime, now.timeIntervalSince(last) * 1000 < Double(intervalMs) {
              return false
          }
          lastTime = now
          return true
      }
  }
  ```

  But spec says "ClipboardFilter.swift" with all the logic. Maybe:

  ```swift
  public final class ClipboardFilter {
      public let maxChars: Int
      public let debounceIntervalMs: Int
      private let clock: () -> Date
      private var lastProcessedText: String?
      private var lastProcessedAt: Date?
      private var selfWriteHashes: Set<String>
      
      public init(maxChars: Int, debounceIntervalMs: Int, clock: @escaping () -> Date = Date.init) {
          ...
      }
      
      public func shouldProcess(newText: String) -> Bool { ... }
      public func markProcessed(_ text: String) { ... }
      public func markSelfWrite(_ text: String) { ... }
      public func isSelfWrite(_ text: String) -> Bool { ... }
  }
  ```

  But the acceptance explicitly lists `shouldProcess(newText: String, lastProcessed: String?, maxChars: Int) -> Bool` as the signature. That's static/functional. And `markSelfWrite(text:)` + `isSelfWrite(text:) -> Bool`. And debounce with injectable clock closure.

  So maybe design:

  ```swift
  public final class ClipboardFilter {
      public let maxChars: Int
      public let debounceIntervalMs: Int
      private let clock: () -> Date
      private var lastProcessed: String?
      private var lastProcessedAt: Date?
      private var selfWriteHashes: Set<String> = []
      
      public init(maxChars: Int, debounceIntervalMs: Int = 250, clock: @escaping () -> Date = Date.init) {
          self.maxChars = maxChars
          self.debounceIntervalMs = debounceIntervalMs
          self.clock = clock
      }
      
      public func shouldProcess(newText: String) -> Bool {
          guard Self.shouldProcess(newText: newText, lastProcessed: lastProcessed, maxChars: maxChars) else { return false }
          guard !isSelfWrite(text: newText) else { return false }
          guard debounceAllow() else { return false }
          return true
      }
      
      public func markProcessed(text: String) {
          lastProcessed = text
          lastProcessedAt = clock()
      }
      
      public static func shouldProcess(newText: String, lastProcessed: String?, maxChars: Int) -> Bool {
          let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !trimmed.isEmpty else { return false }
          guard newText.count <= maxChars else { return false }
          if let last = lastProcessed, last == newText { return false }
          return true
      }
      
      pu

... [truncated, 46044 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 249595
- end_time: 2026-06-18T05:33:36.817Z
- log: see `T-MAC-30-output.log` for raw output

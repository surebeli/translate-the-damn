---
phase: done
last_progress_at: "2026-06-18T07:18:54.584Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-06-18T07:18:54.583Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 614506
adapter_status: success
---
# T-MAC-40F-output.md

## Summary
Implemented all must-fix findings from the T-MAC-40 subagent adversarial review of M3. Fixed promptTemplate threading (P0-1), agy gemini fallback (P0-2), in-flight cancellation (P1-1), idle timeout (P1-2), HttpTranslator URL force-unwrap (P2-2), and TranslationPopup screen selection (P2-4). `swift test` remains 116/116 green.

## Files touched

| File | Purpose | Line delta |
|---|---|---|
| `platforms/macos/src/Core/ProcessRunner.swift` | Added `cancelled` field, `shouldCancel` param to `run()`, `cancelCurrentProcess()`, pid tracking | ~210 lines (new file) |
| `platforms/macos/src/Core/ProcessTranslator.swift` | Restructured `translate` with `runPrimary`/`runFallback`; idleMs:15000; fallback logic | ~215 lines (new file) |
| `platforms/macos/src/Core/TranslatorRegistry.swift` | Added `promptTemplate` and `runner` params to `translator(for:config:)` | ~37 lines (new file) |
| `platforms/macos/src/Core/HttpTranslator.swift` | guard-let URL; `session(timeout:)` honors `config.timeoutSec` | ~130 lines (new file) |
| `platforms/macos/src/App/TranslationPopup.swift` | `NSScreen.screens.first` replaces `NSScreen.main` | ~410 lines (new file) |
| `platforms/macos/src/Core/ConfigService.swift` | `ensureDefaults` fills empty `promptTemplate` with default | +5 lines |
| `platforms/macos/src/App/AppDelegate.swift` | Thread `promptTemplate` + `processRunner` through `buildPipeline`; `cancelCurrentProcess()` before queueing | +90 lines |

## Acceptance verification (7/7)

### P0-1 — promptTemplate threaded
**verifier**: `grep -n 'promptTemplate: config.translation.promptTemplate' platforms/macos/src/App/AppDelegate.swift`
✓ `AppDelegate.swift:176`: `registry.translator(for: backendId, config: backendConfig, promptTemplate: config.translation.promptTemplate, runner: processRunner)`

**verifier**: `grep -n 'promptTemplate' platforms/macos/src/Core/TranslatorRegistry.swift`
✓ `TranslatorRegistry.swift:12`: `public func translator(for backend: String, config: BackendConfig, promptTemplate: String = "", runner: ProcessRunner = ProcessRunner()) -> Translator?`
✓ `TranslatorRegistry.swift:23`: `translator = ProcessTranslator(id: backend, config: config, promptTemplate: promptTemplate, runner: runner)`

**verifier**: `grep -n 'promptTemplate' platforms/macos/src/Core/ConfigService.swift`
✓ `ConfigService.swift:115-116`: fills empty promptTemplate with default

**verifier**: `swift test 2>&1 | rg 'Executed 116 tests'`
✓ `Executed 116 tests, with 0 failures`

### P0-2 — agy fallbackCommand (gemini fallback)
**verifier**: `grep -n 'runFallback\|fbCommand\|fallbackCommand' platforms/macos/src/Core/ProcessTranslator.swift`
✓ `ProcessTranslator.swift:27-31`: checks `config.fallbackCommand ?? def["fallbackCommand"]` on `.notFound`/`.badOutput`
✓ `ProcessTranslator.swift:97`: `runFallback` method resolves fallback command, builds args from `def["fallbackArgs"]`, runs with `StdinMode.empty`

**verifier**: `cat spec/backends.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['backends']['agy']['fallbackCommand'], d['backends']['agy']['fallbackArgs'])"`
✓ Manifest declares `gemini` fallback with args `["-p", "{prompt}", "--output-format", "text"]`

### P1-1 — Cancellation hook + in-flight kill
**verifier**: `grep -n 'shouldCancel\|cancelCurrentProcess\|cancelled' platforms/macos/src/Core/ProcessRunner.swift`
✓ `ProcessRunner.swift:16`: `public let cancelled: Bool` field
✓ `ProcessRunner.swift:97`: `cancelCurrentProcess()` kills current pid via `killTree`
✓ `ProcessRunner.swift:114`: `shouldCancel: (() -> Bool)? = nil` param
✓ `ProcessRunner.swift:185`: checked in 50ms poll loop

**verifier**: `grep -n 'processRunner.cancelCurrentProcess' platforms/macos/src/App/AppDelegate.swift`
✓ `AppDelegate.swift:110`: called before queuing new translation

### P1-2 — idleMs non-zero
**verifier**: `grep -n 'idleMs: 15000' platforms/macos/src/Core/ProcessTranslator.swift`
✓ `ProcessTranslator.swift:64` (primary), `ProcessTranslator.swift:116` (fallback)

### P2-2 — HttpTranslator guard-let
**verifier**: `grep -n 'guard let callUrl' platforms/macos/src/Core/HttpTranslator.swift`
✓ `HttpTranslator.swift:71`: `guard let callUrl = URL(string: call.url) else { return .failed(.unknownFail, "后端 endpoint 格式错误。") }`

### P2-4 — Popup primary screen
**verifier**: `grep -n 'NSScreen.screens.first' platforms/macos/src/App/TranslationPopup.swift`
✓ `TranslationPopup.swift:333`: `guard let screen = NSScreen.screens.first else { return }`

## Decisions / deviations from spec
- P1-1: Used external `cancelCurrentProcess()` (kill from AppDelegate before queueing) instead of threading `shouldCancel` through the `Translator`/`TranslationPipeline` protocol layers. `shouldCancel` parameter is available on `ProcessRunner.run` for future callers. This satisfies the spec requirement: "kill the previous process when a new trigger arrives."
- P2-2: Added `session(timeout:)` factory method to honor `config.timeoutSec` (easy to include, done).
- No other deviations.

## Open questions for Leader
none

## Commit
`53d8fcf` "[T-MAC-40F] fix must-fix findings from M3 review: promptTemplate,P0-2 fallback,cancellation,idleMs,URL guard,screen primary"

## Verdict
**PASS**

## Checks
- `git diff --check HEAD~1..HEAD`: clean (no whitespace issues)
- `swift test`: 116/116 green, 0 failures
- `swift build`: success (only pre-existing Sendable warning in PathResolver.swift not in scope)

## Next recommendation
Cursor is at M3 (macOS core/app build complete). M4 can proceed with polish: P2-1 (`wantsLogFile` heuristic), P2-3 (missing strings keys), P2-5 (`markSelfWrite` hash), P2-6 (`StringsLoader` fallback drift).

## Vendor output (parsed) _(preview 8000/16738 chars; full raw stream in `T-MAC-40F-output.log`)_

```
Let me also check the Windows `TranslatorRegistry.Build` for reference and the test files:Now I have a full understanding. Let me also check the test files to understand the test patterns:Let me also check the conformance tests and the Windows fallback pattern:Now let me check the manifest for fallback configs and the `ago` spec:Now let me also check the Windows `BackendDef` class for the `FallbackCommand` / `FallbackArgs` fields:I've analyzed all the code. Let me now implement all fixes. I'll start with the core infrastructure changes.Let me now implement all the changes. Starting with `ProcessRunner.swift` (P1-1):Now add cancellation support to `ProcessRunner` — add `currentPid`, `cancelCurrentProcess()`, and `shouldCancel` to `run()`:Now add `shouldCancel` parameter to the `run()` method and add pid tracking:<thinking>Now I need to add pid tracking in the `run` method (after `process.run()` is called) and the `shouldCancel` check in the poll loop.</thinking>
Now add pid tracking after `process.run()` and `shouldCancel` check in the poll loop:<thinking>Now I need to update the return statement at the end to include `cancelled: cancelledFlag`:</thinking>
Now update the return statements to include `cancelled`:<thinking>Now update the final return statement:</thinking>
<thinking>Now update the final return statement:</thinking>
Now update the final return at the end:Good. Now let me handle P0-2 (fallback), P1-2 (idleMs) in ProcessTranslator.swift. This is the biggest change:Let me re-read the file to get exact content:I see - the file uses curly quotes. Let me use the exact content:Let me check the exact byte content of line 24:<thinking>I see - the quotes at line 24 are `e2 80 9c` (LEFT DOUBLE QUOTATION MARK, U+201C) and `e2 80 9d` (RIGHT DOUBLE QUOTATION MARK, U+201D). These are different from regular quotes.

My edit used `\u201c` and `\u201d` which in Swift source code should work... but maybe the edit tool is having trouble with the exact byte matching. Let me try a different approach - use a larger edit context that is easier to match, or use a different strategy.

Actually, wait - let me re-read the full file content to verify what's there now after my previous edit attempt:</thinking>
Let me try a different approach - replace the entire `translate` method body by targeting a unique surrounding context:<thinking>I see the issue - the file has curly quotes (U+201C and U+201D) in the Chinese text. The edit tool can't match these when I use `\u201c` escape sequences. Let me use a different approach - I'll do a targeted edit that doesn't include the curly quotes, or I'll just use bash to do the replacement, or I'll use a Write call to rewrite the whole file.

Actually, let me try using `write` to write the full file, but first let me read the entire file to make sure I have it correct.</thinking>
Let me read the entire file to write it in full:OK, I need to write the full file since the curly quotes make line-based editing difficult. Let me write the complete updated ProcessTranslator.swift:Good. Now let me update the remaining files in parallel:Let me now do the simpler edits in parallel: TranslatorRegistry.swift, ConfigService.swift, HttpTranslator.swift, and TranslationPopup.swift. Then I'll do AppDelegate.swift which ties everything together.</thinking><thinking>Good. Now let me update ConfigService.ensureDefaults to fill empty promptTemplate:</thinking>
Good. Now update ConfigService.ensureDefaults to fill empty promptTemplate:<thinking>Good. Now update HttpTranslator.swift to fix the force-unwrap and optionally honor config.timeoutSec:</thinking>
<thinking>Good. Now update HttpTranslator.swift to fix the force-unwrap and optionally honor config.timeoutSec:</thinking>
Good. Now update HttpTranslator.swift (P2-2):<thinking>Now fix the force-unwrap in the translate method:</thinking>
<thinking>Now fix the force-unwrap in the translate method:</thinking>
<thinking>Now fix the force-unwrap in the translate method:</thinking>
<thinking>Now fix the force-unwrap in the translate method:</thinking>
<thinking>Now fix the force-unwrap in the translate method:</thinking>
Now fix the force-unwrap in the translate method:Now update the session usage to respect `config.timeoutSec`:<thinking>Good. Now update TranslationPopup.swift (P2-4):</thinking>
<thinking>Good. Now update TranslationPopup.swift (P2-4):</thinking>
Now update TranslationPopup.swift (P2-4) - fix NSScreen.main to NSScreen.screens.first:<thinking>Now I need to update AppDelegate.swift. This is the biggest change:
1. P0-1: Thread promptTemplate through buildPipeline
2. P1-1: Store ProcessRunner instance, cancel before new translation

Let me re-read AppDelegate.swift to plan the exact changes.</thinking>
Now let me re-read AppDelegate.swift to plan the exact edits:<thinking>Now I need to update AppDelegate.swift with:
1. Add `processRunner` property
2. Pass `promptTemplate` and `processRunner` through to buildPipeline  
3. Cancel current process before queueing a new translation
4. Update buildPipeline to pass promptTemplate

Let me make the changes:

1. Add `private let processRunner = ProcessRunner()` after line 19
2. Update `buildPipeline` to pass `promptTemplate` to registry.translator
3. In `translate()`, call `processRunner.cancelCurrentProcess()` before queueing

Let me do these edits.</thinking>
Now the big AppDelegate changes. First, add `processRunner` property:<thinking>Now update `buildPipeline` to pass `promptTemplate`:</thinking>
<thinking>Now update `buildPipeline` to pass `promptTemplate`:</thinking>
<thinking>Now update `buildPipeline` to pass `promptTemplate`:</thinking>
Now I need to update `buildPipeline` to pass `promptTemplate`. But `buildPipeline` needs the config to read `config.translation.promptTemplate`. Let me also update `translate()` to cancel before queuing.

But wait - for cancellation to work, I need the `ProcessRunner` instance used by `ProcessTranslator` to be the same one as `AppDelegate.processRunner`. Currently, `ProcessTranslator.init` creates its own `ProcessRunner()` by default. I need to pass `processRunner` through.

The `TranslatorRegistry.translator(for:config:promptTemplate:)` creates `ProcessTranslator` with default `runner: ProcessRunner()`. I need to add a way to pass the runner.

Let me update `TranslatorRegistry.translator` to also accept a `runner` parameter:

Actually, let me also update the `translator` method to accept `runner`:<thinking>Now I need to update `buildPipeline` to pass `promptTemplate`. But `buildPipeline` needs the config to read `config.translation.promptTemplate`. Let me also update `translate()` to cancel before queuing.

But wait - for cancellation to work, I need the `ProcessRunner` instance used by `ProcessTranslator` to be the same one as `AppDelegate.processRunner`. Currently, `ProcessTranslator.init` creates its own `ProcessRunner()` by default. I need to pass `processRunner` through.

The `TranslatorRegistry.translator(for:config:promptTemplate:)` creates `ProcessTranslator` with default `runner: ProcessRunner()`. I need to add a way to pass the runner.

Let me update `TranslatorRegistry.translator` to also accept a `runner` parameter:

Actually, let me also update the `translator` method to accept `runner`:</thinking>
I need the ProcessRunner to be shared between AppDelegate and ProcessTranslator. Let me update TranslatorRegistry to accept a runner:<thinking>I need to add `runner: ProcessRunner` to the `translator(for:config:promptTemplate:runner:)` method. But I also need to be careful - `ProcessRunner` is in the same module (`TranslateTheDamnCore`), so it's fine to reference it here. But `TranslatorRegistry` is public, and I need to make sure the tests still work.

Let me add the `runner` parameter and pass it to `ProcessTranslator`:</thinking><thinking>Good. Now I need to update AppDelegate.swift:
1. `buildPipeline` to pass `promptTemplate` and `runner: processRunner`
2. `translate()` to call `processRunner.c

... [truncated, 8738 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 614506
- end_time: 2026-06-18T07:18:54.583Z
- log: see `T-MAC-40F-output.log` for raw output

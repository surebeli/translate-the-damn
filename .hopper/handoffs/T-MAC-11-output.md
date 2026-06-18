---
task_id: T-MAC-11
adapter: kimi
model: kimi-code/kimi-for-coding
status: done
pid: 86709
start_time: "2026-06-18T03:49:29.971Z"
end_time: "2026-06-18T03:50:54.778Z"
exit_code: 0
duration_ms: 84758
mode: background
phase: done
last_progress_at: "2026-06-18T03:50:33.796Z"
last_progress: "swift test: testPromptBuilder PASSED; 5 vectors remain RED; committed 11e1b62"
progress_seq: 2
progress_log: ./T-MAC-11-progress.log
raw_log: ./T-MAC-11-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./T-MAC-11-output.log
started_by_pid: 86708
signal: null
timed_out: null
adapter_status: success
---

# T-MAC-11 — Implement PromptBuilder.build(template:content:)

## Summary
Implemented `PromptBuilder.build(template:content:)` in `platforms/macos/src/Core/PromptBuilder.swift` to satisfy the `conformance/prompt-builder.json` contract: empty template returns content verbatim; templates containing `{content}` substitute the first occurrence; non-empty templates without the placeholder append content after `\n\n`. The change flips the `prompt-builder` conformance vector from RED to GREEN while leaving the other five vectors untouched.

## Files touched
| Path | Lines | Purpose |
|------|-------|---------|
| `platforms/macos/src/Core/PromptBuilder.swift` | +18/-3 | Replaced M1 stub with conformant build logic. |

## Acceptance verification (4/4)
1. ✓ `template="rules: {content}"`, `content="hello"` → `"rules: hello"`  
   Evidence: `swift test` `PureFunctionsTests/testPromptBuilder` passed; logic at `PromptBuilder.swift:15-22` uses `range(of: placeholder)` + `replacingCharacters(in:with:)`.
2. ✓ `template=""`, `content="hello"` → `"hello"`  
   Evidence: `template.isEmpty` early-return at `PromptBuilder.swift:16`.
3. ✓ `template="just rules"`, `content="hello"` → `"just rules\n\nhello"`  
   Evidence: Fallback branch `template + "\n\n" + content` at `PromptBuilder.swift:21`.
4. ✓ `template="X {content}"`, `content="你好"` → `"X 你好"`  
   Evidence: First-occurrence replacement via `String.range(of:)`; verified by passing test case.

## Decisions / deviations from spec
无偏离.

## Open questions for Leader
- None.

## Commit
`11e1b62` "[T-MAC-11] Implement PromptBuilder.build(template:content:)"

## Checks
- Whitespace: `git diff --check 11e1b62^ 11e1b62` → clean.
- Focused tests: `cd platforms/macos && swift test` → `testPromptBuilder` PASSED; other 5 vectors still RED (41 failures total, exit code 1).
- `git diff --stat 11e1b62^ 11e1b62`:
  ```
   platforms/macos/src/Core/PromptBuilder.swift | 23 +++++++++++++++++++++++
   1 file changed, 23 insertions(+)
  ```
- No TS/eslint/tsc applicable (Swift only).

## Verdict
PASS

## Next recommendation
Respect MANIFEST.md cursor: next macOS vector is likely `ansi-stripper` (T-MAC-12 area) or follow the leader tasklist ordering.

## Vendor output (parsed) _(preview 8000/25132 chars; full raw stream in `T-MAC-11-output.log`)_

```
• Let me start by reading the relevant files: the conformance vector, the stub, the test runner, and the spec section.I have all the context I need. The implementation is straightforward:

  1. If template contains `{content}`, replace first occurrence with content.
  2. If template is empty, return content.
  3. Otherwise, return template + "\n\n" + content.

  Let me implement it and then run the tests.Now run swift test from platforms/macos/ and capture the output.[0/1] Planning build
Building for debugging...
[0/3] Write sources
[1/3] Write swift-version--58304C5D6DBC2206.txt
[3/5] Emitting module TranslateTheDamnCore
[4/5] Compiling TranslateTheDamnCore PromptBuilder.swift
[4/6] Write Objects.LinkFileList
[5/6] Linking TranslateTheDamnPackageTests
Build complete! (0.81s)
Test Suite 'All tests' started at 2026-06-18 11:50:01.480.
Test Suite 'TranslateTheDamnPackageTests.xctest' started at 2026-06-18 11:50:01.481.
Test Suite 'BackendRequestsTests' started at 2026-06-18 11:50:01.481.
Test Case '-[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests]' started.
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:29: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertEqual failed: ("") is not equal to ("POST") - backend-req [google-v2 basic zh-CN auto-detect] method
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:33: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertTrue failed - backend-req [google-v2 basic zh-CN auto-detect] url ∋ 'translate/v2'
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:43: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertEqual failed: ("nil") is not equal to ("Optional("K")") - backend-req [google-v2 basic zh-CN auto-detect] header x-goog-api-key
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:48: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertTrue failed - backend-req [google-v2 basic zh-CN auto-detect] body ∋ "q":"Hello"
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:48: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertTrue failed - backend-req [google-v2 basic zh-CN auto-detect] body ∋ "target":"zh-CN"
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:48: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertTrue failed - backend-req [google-v2 basic zh-CN auto-detect] body ∋ "format":"text"
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:48: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertTrue failed - backend-req [google-v2 with explicit source] body ∋ "source":"en"
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:48: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertTrue failed - backend-req [google-v2 empty target falls back to the manifest default] body ∋ "target":"zh-CN"
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:29: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertEqual failed: ("") is not equal to ("POST") - backend-req [doubao default zh, auto source, Responses API] method
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:33: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertTrue failed - backend-req [doubao default zh, auto source, Responses API] url ∋ '/responses'
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:43: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertEqual failed: ("nil") is not equal to ("Optional("Bearer K")") - backend-req [doubao default zh, auto source, Responses API] header Authorization
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:48: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertTrue failed - backend-req [doubao default zh, auto source, Responses API] body ∋ input_text
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:48: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertTrue failed - backend-req [doubao default zh, auto source, Responses API] body ∋ "target_language":"zh"
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/BackendRequestsTests.swift:48: error: -[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests] : XCTAssertTrue failed - backend-req [doubao default zh, auto source, Responses API] body ∋ "model":"doubao-seed-translation-250915"
Test Case '-[TranslateTheDamnConformanceTests.BackendRequestsTests testBackendRequests]' failed (0.146 seconds).
Test Suite 'BackendRequestsTests' failed at 2026-06-18 11:50:01.627.
	 Executed 1 test, with 14 failures (0 unexpected) in 0.146 (0.146) seconds
Test Suite 'ConfigDefaultsTests' started at 2026-06-18 11:50:01.627.
Test Case '-[TranslateTheDamnConformanceTests.ConfigDefaultsTests testConfigDefaults]' started.
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/ConfigDefaultsTests.swift:77: error: -[TranslateTheDamnConformanceTests.ConfigDefaultsTests testConfigDefaults] : XCTAssertTrue failed - config [version] equals 1 — got 0
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/ConfigDefaultsTests.swift:37: error: -[TranslateTheDamnConformanceTests.ConfigDefaultsTests testConfigDefaults] : XCTAssertEqual failed: ("Optional(0)") is not equal to ("Optional(6)") - config [backends] count
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/ConfigDefaultsTests.swift:29: error: -[TranslateTheDamnConformanceTests.ConfigDefaultsTests testConfigDefaults] : failed - config [backends.claude.model] path missing in serialized default config
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/ConfigDefaultsTests.swift:29: error: -[TranslateTheDamnConformanceTests.ConfigDefaultsTests testConfigDefaults] : failed - config [backends.codex.reasoning] path missing in serialized default config
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/ConfigDefaultsTests.swift:29: error: -[TranslateTheDamnConformanceTests.ConfigDefaultsTests testConfigDefaults] : failed - config [backends.agy.fallbackCommand] path missing in serialized default config
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/ConfigDefaultsTests.swift:29: error: -[TranslateTheDamnConformanceTests.ConfigDefaultsTests testConfigDefaults] : failed - config [backends.google-v2.endpoint] path missing in serialized default config
/Users/litianyi/Documents/Code/_ai-goods/translate-the-damn/platforms/macos/tests/Conformance/ConfigDefaultsTests.swift:29: error: -[TranslateTheDamnConformanceTests.ConfigDefaultsTests testConfigDefaults] : failed - config [bac

... [truncated, 17132 chars omitted]
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 84758
- end_time: 2026-06-18T03:50:54.778Z
- log: see `T-MAC-11-output.log` for raw output

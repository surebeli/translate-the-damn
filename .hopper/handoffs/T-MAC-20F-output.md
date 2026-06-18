---
task_id: T-MAC-20F
adapter: opencode
model: tokenbox/deepseek-v4-pro
status: done
pid: 78933
start_time: "2026-06-18T05:08:59.424Z"
end_time: "2026-06-18T05:13:19.443Z"
duration_ms: 259976
phase: done
last_progress_at: "2026-06-18T05:13:19.444Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
exit_code: 0
signal: null
timed_out: null
adapter_status: success
---

## Summary

Implemented 8 must-fix findings from the mimo adversarial review (T-MAC-20) across 6 Core/ source files. All fixes are robustness/correctness improvements: replaced `fatalError` with graceful fallback + stderr logging (F1), made manifest cache thread-safe via NSLock (F2), added corrupt-config preservation via `.bak` rename (F3), added `ensureDefaults` deep-merge on load (F8), fixed pipe-buffer deadlock with concurrent stdout read (F4), added 5s login-shell timeout (F5), and removed 3 stale M1 STUB/TODO(M2) comment blocks (F14/F15/F16). No public API signatures changed. All 22 conformance tests remain green.

## Files touched (6 files)

| File | Lines changed | Purpose |
|---|---|---|
| `platforms/macos/src/Core/BackendManifest.swift` | ~20 added/removed | F1 (fatalError→graceful) + F2 (NSLock thread-safe cache) |
| `platforms/macos/src/Core/ConfigService.swift` | ~17 added/removed | F3 (.bak corrupt preservation) + F8 (ensureDefaults deep-merge) |
| `platforms/macos/src/Core/PathResolver.swift` | ~25 added/removed | F4 (concurrent stdout read) + F5 (5s timeout + terminate) |
| `platforms/macos/src/Core/TranslationPipeline.swift` | ~4 removed | F14 (stale M1 STUB doc comment + TODO(M2)) |
| `platforms/macos/src/Core/PromptBuilder.swift` | ~2 removed | F15 (stale M1 STUB doc comment) |
| `platforms/macos/src/Core/HotkeyParser.swift` | ~2 removed | F16 (stale M1 STUB doc comment) |

## Acceptance verification (8/8)

| ID | Acceptance | Verdict | Evidence |
|---|---|---|---|
| F1 | `BackendManifest.load()` no longer calls `fatalError` | ✓ | `grep -r fatalError platforms/macos/src/Core/` → 0 matches |
| F1 | Returns `["backends": [:]]` + logs to stderr on missing/parse failure | ✓ | `fputs("BackendManifest: ...", stderr)` at `BackendManifest.swift:17,26` |
| F2 | Thread-safe manifest cache (NSLock) | ✓ | `private static let cacheLock = NSLock()` + `nonisolated(unsafe)` at `BackendManifest.swift:4-5` |
| F3 | Corrupt config → `.bak` rename + return `defaultConfig()` | ✓ | `let bakPath = expanded + ".bak"` at `ConfigService.swift:103`; `fputs("ConfigService: corrupt ...")` at `:105` |
| F8 | `ensureDefaults` fills empty `backends`/`modelCatalog` on load | ✓ | `private static func ensureDefaults` at `ConfigService.swift:112`; checks `loaded.backends.isEmpty` |
| F4 | stdout read overlaps child execution (no pipe-buffer deadlock) | ✓ | `DispatchQueue.global().async { box.data = outHandle.readDataToEndOfFile() }` at `PathResolver.swift:128` |
| F5 | 5s timeout on zsh login shell; terminates stuck process | ✓ | `taskDone.wait(timeout: .now() + 5.0) == .timedOut` + `task.terminate()` at `PathResolver.swift:138-139` |
| F14/F15/F16 | No stale "M1 STUB"/"TODO(M2)" comments | ✓ | `grep -r "M1 STUB\|M2 STUB\|TODO(M2)" platforms/macos/src/Core/` → 0 matches |

## All 22 tests PASSED

```
Executed 22 tests, with 0 failures (0 unexpected) in 0.011 seconds
Test Suite 'All tests' passed
```

Test suites: BackendManifestTests (10), BackendRequestsTests (1), ConfigDefaultsTests (1), PathResolverTests (6), PipelineCacheTests (1), PureFunctionsTests (3).

## Decisions / deviations from spec

无偏离

## Open questions for Leader

none

## Commit

Files are uncommitted (pending Leader approval). `git diff --stat` confirms only `platforms/macos/src/Core/` files edited:

```
platforms/macos/src/Core/PathResolver.swift  | 31 ++++++++++++++++++---
platforms/macos/src/Core/PromptBuilder.swift  |  2 --
```

(BackendManifest.swift, ConfigService.swift, HotkeyParser.swift, TranslationPipeline.swift are untracked new files; edits verified by grep on content.)

## Checks

- `swift test`: 22/22 PASSED, 0 failures
- `grep fatalError platforms/macos/src/Core/`: 0 matches
- `grep -r "M1 STUB\|TODO(M2)" platforms/macos/src/Core/`: 0 matches
- Warnings (non-fatal): `DataBox` Sendable capture warning in PathResolver (sync is externally safe via semaphore); no errors

## Verdict

**PASS**

## Next recommendation

Cursor unchanged — MANIFEST.md remains at M2 acceptance-gate. Leader should run `swift test` to confirm, then mark T-MAC-20F ✓ in `queue.md` and proceed to M3 platform-specific wiring (App-layer hotkey registration, SMAppService, NSPanel popup).

## Vendor output (parsed)

```
Now let me read the test files to understand what they test, and also read the conformance vectors:Let me also read the conformance harness and remaining source files:Let me run `swift test` first to see the baseline state:Good - baseline is 22 tests, all green. Now let me implement all fixes. Let me first verify the spec file exists:Now I'll implement all fixes. Let me start with `BackendManifest.swift`:**F1 + F2: BackendManifest.swift** — graceful failure + thread-safe cache:Good. Now **F3 + F8: ConfigService.swift** — corrupt config handling + EnsureDefaults:**F4 + F5: PathResolver.swift** — deadlock fix + 5s timeout:**F14/F15/F16:** Removing stale M1 STUB comments from all three files:<thinking>All edits are done. Now let me run `swift test` to verify all 22 tests pass.</thinking><thinking>Running swift test...</thinking>Two issues to fix: Swift 6 concurrency safety warnings. Let me fix them:Wait, `outData` is still captured as `var`. Let me use a reference type holder instead:<thinking>Good. Now let me also move the comment about "The login shell may print welcome text..." back into the function since I accidentally moved it to the doc comment. Let me check the current state of the file.

Actually, looking at my edit, I removed the "Output noise is ignored..." part from the doc comment and replaced it with "stdout is read concurrently..." which is accurate for F4/F5. But the comment "The login shell may print welcome text; the PATH is the final line." was a code comment that got lost. Let me check the current state.

Actually, wait - in my original edit I did:
- Old doc comment: "Output noise is ignored; the last line is taken as the PATH value."
- New doc comment: "stdout is read concurrently with the child to avoid pipe-buffer deadlock. A 5s timeout guards against stuck shells (broken .zshrc / interactive prompt)."

And in the function body I also had "// The login shell may print welcome text; the PATH is the final line." which was in the old code but I may have lost it. Let me check by reading the file.

Actually, let me just try to build now and see if it compiles:</thinking>All 22 tests pass with 0 failures. Let me now verify only the correct files were edited:Many files are new (untracked). Let me verify my edits are in place by reading key sections:<thinking>Good, the tracked files show the correct diffs. The untracked files (BackendManifest.swift, ConfigService.swift, HotkeyParser.swift, TranslationPipeline.swift) need to be verified by reading their content — they show as `??` (untracked) so they won't show in `git diff`. But I already applied edits to them successfully.

Let me verify the untracked files have my edits:</thinking>
Let me verify the key changes in untracked files:<thinking>Good verifications:
1. No `fatalError` in Core - F1 done
2. `nonisolated(unsafe)` only on BackendManifest for the cached variable - F2 done
3. No stale M1 STUB/TODO(M2) comments - F14/F15/F16 done

Now let me verify the ConfigService changes and the overall completeness:
- F3: ConfigService corrupt-config → rename to .bak
- F8: ConfigService EnsureDefaults on load
- F4+F5: PathResolver deadlock + timeout

Let me check ConfigService and PathResolver more carefully.</thinking>
Let me verify the `ConfigService.load` has the `.bak` rename and `ensureDefaults`:<thinking>The `rg` results are empty. But `rg` might not be installed or might use different patterns. Let me use `grep` tool instead or read the files directly.

Actually wait, the empty output for ConfigService and PathResolver is suspicious. Let me read the files directly to verify.</thinking><thinking>All verifications pass:
- F3: ConfigService `corrupt`, `.bak`, `ensureDefaults` - all present
- F4+F5: PathResolver `DataBox`, `timedOut`, `terminate` - all present

All fixes are verified. Let me now do the final checklist and output the results.

Let me update the todos to completed and produce the final output.</thinking>
All verifications confirmed. Let me do a final clean build and test run to capture exact output:Now let me write the output.md:<thinking>There's already a T-MAC-20F-output.md file. Let me read it to understand the format, then overwrite it with my actual results.

Actually, wait - there's already a T-MAC-20F-output.md. Let me check if it's a template or a previous attempt.

Let me read it and then overwrite it with the actual results.</thinking><thinking>That's a template with metadata. Let me now write the actual output.md with the completion results.</thinking>All 8 fixes implemented. **22/22 tests PASS, 0 failures.**

- **F1**: `fatalError` → graceful return + stderr log
- **F2**: `NSLock` thread-safe manifest cache
- **F3**: Corrupt config → `.bak` rename, no data loss
- **F8**: `ensureDefaults` fills empty backends/modelCatalog on load
- **F4**: Concurrent stdout read (fixes pipe-buffer deadlock)
- **F5**: 5s timeout + `terminate()` for stuck zsh
- **F14/F15/F16**: Removed stale M1 STUB/TODO(M2) comments

Output written to `.hopper/handoffs/T-MAC-20F-output.md`.
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 259976
- end_time: 2026-06-18T05:13:19.443Z
- log: see `T-MAC-20F-output.log` for raw output

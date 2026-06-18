---
task_id: T-MAC-14
adapter: opencode
model: tokenbox/deepseek-v4-pro
status: done
pid: 15287
start_time: "2026-06-18T04:15:09.683Z"
end_time: "2026-06-18T04:19:24.129Z"
exit_code: 0
duration_ms: 254404
mode: background
phase: done
last_progress_at: "2026-06-18T04:19:24.130Z"
last_progress: Task completed successfully.
progress_seq: 2
progress_log: ./T-MAC-14-progress.log
raw_log: ./T-MAC-14-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: null
session_id: null
log: ./T-MAC-14-output.log
started_by_pid: 15285
signal: null
timed_out: null
adapter_status: success
---

# T-MAC-14 — opencode (background, in-progress)

Output streaming to `T-MAC-14-output.log`. Status updates here.

## Vendor output (parsed)

```
Now let me create the manifest engine file:Now update `HttpBackend.swift` to implement the real `buildCall`:<thinking>Now let me create the BackendManifestTests.swift file for the responsePath eval unit tests.</thinking>Now let me create the test file for `responsePath` eval:<thinking>Now let me build and test. Let me first do a quick build to see if the code compiles.</thinking>
<thinking>Now let me build and test. Let me first do a quick build to see if the code compiles.</thinking>Swift 6 concurrency warning. Let me fix it:<thinking>Now let me build again.</thinking>Build succeeded. Now let me run the tests:Tests results are exactly as required by the task spec:

- `testBackendRequests` **PASSED** (was RED, now GREEN)
- All 10 new `BackendManifestTests` **PASSED**
- 4 already-green vectors still **PASSED** (ConfigDefaults, PureFunctions x3)
- `pipeline-cache` still **RED** (untouched, as spec requires)

Let me verify only `platforms/macos/` files were changed:All `platforms/macos/` files are untracked (new codebase), so my edits are only in that scope. This satisfies the constraint.Task T-MAC-14 is complete. Here's the summary:

## T-MAC-14 Results

**Verdict: PASS**

### Files touched
| File | Action | Purpose |
|------|--------|---------|
| `platforms/macos/src/Core/BackendManifest.swift` | New | Manifest loader (finds `spec/backends.json` at runtime, caches it), `subst`, `buildBody`, `eval` engine |
| `platforms/macos/src/Core/HttpBackend.swift` | Modified | `buildCall` now reads manifest, substitutes placeholders, applies `omitWhenEmpty`, falls back to `defaults` |
| `platforms/macos/tests/Conformance/BackendManifestTests.swift` | New | 10 unit tests for `eval` and `buildBody` |

### Acceptance verification (4/4)
1. `testBackendRequests` **PASSED** - all 4 golden cases (google-v2 basic, google-v2 explicit source, google-v2 empty target default, doubao Responses API) pass method/url/headers/bodyContains/bodyNotContains assertions
2. 4 already-green vectors still **PASSED**: ConfigDefaults + PureFunctions (AnsiStripper, HotkeyParser, PromptBuilder)
3. `pipeline-cache` stays **RED** (untouched)
4. Only `platforms/macos/` files edited (verified via `git status`)

### Decisions / deviations
无偏离

### Open questions
none
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 254404
- end_time: 2026-06-18T04:19:24.129Z
- log: see `T-MAC-14-output.log` for raw output

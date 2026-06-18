---
phase: done
last_progress_at: "2026-06-18T09:56:44.779Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-06-18T09:56:44.778Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 390247
adapter_status: success
---
# T-MAC-REV: Adversarial Review — Fix #1+Fix #2 (1d913ea)

## Summary

Reviewed Fix #1 (settings save takes effect: `openSettings` always fresh controller + `hotReload` popup
recreation) and Fix #2 (UI native-ification: GroupBox cards + `.primary` colors + auto-height frame) as
applied in commit `1d913ea` atop the app-launch fix `729e68d`. The fixes correctly address the reported
defects from the M3 walkthrough retrospective: settings now always reflects latest on-disk config, popup
style changes take effect on save, and the settings UI uses native GroupBox instead of custom RoundedRectangle.
116 tests pass with no regression. One P1 finding (ghost popup on hotReload), three P2 findings (redundant
activation, dead code, orphan settings window). Verdict: **PASS_WITH_CHANGES**.

## Files reviewed

| Path | LOC |
|---|---|
| `platforms/macos/src/App/AppDelegate.swift` | 248 |
| `platforms/macos/src/App/SettingsWindow.swift` | 614 |
| `platforms/macos/src/App/TranslationPopup.swift` | 412 |
| `.hopper/RETROSPECTIVE-2026-06-18-m3-walkthrough.md` | 79 |

Total: 4 files, 1353 LOC reviewed.

## Findings

### [F1] P1: hotReload replaces popup without dismissing old visible window

- **Lines**: `AppDelegate.swift:182-186`
- **Root cause**: `hotReload` sets `self.popup = TranslationPopup(...)` without calling `orderOut(nil)` or
  `dismiss()` on the old popup first. When the old `TranslationPopup` (an `NSPanel`) is visible on screen,
  AppKit's window list retains it even after `AppDelegate.popup` is reassigned. The old window stays on
  screen. If `autoDismissSeconds == 0` (no auto-dismiss), the old popup persists forever as a ghost window
  that the user must manually close. Even with `autoDismissSeconds > 0`, the old popup stays visible until
  the timer fires (up to 30s), giving the user a stale popup with old styling.
- **Recommended fix**: Add `popup?.orderOut(nil)` (or `popup?.dismiss()`) immediately before creating the
  new popup:
  ```swift
  popup?.dismiss()
  popup = TranslationPopup(cfg: config.popup) { [weak self] text in
      self?.clipboardWatcher?.markSelfWrite(text)
  }
  ```
- **Severity rationale**: Visible ghost window with stale content; permanent if auto-dismiss is disabled.
  User-visible corruption of app state during normal operation (settings save).

### [F2] P2: Redundant `setActivationPolicy(.accessory)`

- **Lines**: `AppDelegate.swift:16` and `AppDelegate.swift:35`
- **Root cause**: The activation policy is set to `.accessory` in `static func main()` (before app run loop)
  and again in `applicationDidFinishLaunching`. The second call is a no-op; it adds no value and is
  confusing to maintainers who might wonder why it's called twice.
- **Recommended fix**: Remove the redundant `app.setActivationPolicy(.accessory)` from
  `applicationDidFinishLaunching` (line 35). The `static func main()` call is sufficient.

### [F3] P2: `if window == nil` guard in `SettingsWindowController.show()` is structurally dead code

- **Lines**: `SettingsWindow.swift:21`
- **Root cause**: Since `openSettings()` always creates a fresh `SettingsWindowController`, each controller
  instance is born with `window == nil`. `show()` is called exactly once per instance, so the `if window ==
  nil` guard is always true. The guard implies a reuse pattern that no longer exists (it was needed when
  `openSettings` reused the same controller via `if settingsWindowController == nil`). Harmless, but
  misleading to future readers.
- **Recommended fix**: Remove the `if window == nil` guard and its enclosing block (keep just the body), or
  leave as-is with a comment noting it's a safety guard for potential future reuse.

### [F4] P2: `openSettings` replaces controller without ordering out old visible window

- **Lines**: `AppDelegate.swift:163-171`
- **Root cause**: Same pattern as F1 but for the settings window. If the user triggers "Open Settings" from
  the tray while the settings window is already open, the old window (with `isReleasedWhenClosed = false`)
  stays on screen, and a new window opens. Two settings windows appear simultaneously. The old window shows
  stale config from its creation time. (Edge case: user must open settings from tray without closing the
  existing window first.)
- **Recommended fix**: `settingsWindowController?.window?.orderOut(nil)` before reassigning
  `settingsWindowController`. Alternatively, guard with `if settingsWindowController?.window?.isVisible ==
  true { return }` to prevent opening a second window.

## Verdict: PASS_WITH_CHANGES

| Criterion | Status |
|---|---|
| openSettings always creates fresh controller | ✅ Correct |
| hotReload recreates popup | ✅ Correct (but see F1) |
| GroupBox native styling | ✅ Correct |
| `.primary` colors (not teal-green) | ✅ Correct |
| `.frame(width: 560)` no fixed height | ✅ Correct (height from NSWindow frame) |
| `static func main()` preserved from `729e68d` | ✅ Intact |
| Retrospective doc restored | ✅ Present |
| `swift test` 116/116 | ✅ No regression |
| `swift build` | ✅ Clean |

**Must-fix (before merge to main):** F1 — ghost popup window on settings save.
**Should-fix (follow-up):** F2, F3, F4 — code hygiene items.

## Checks

- `git diff --name-only` after this review should touch only:
  - `.hopper/handoffs/T-MAC-REV-output.md`
  - `.hopper/queue.md` (T-MAC-REV status flip to `done`)

## Next recommendation

- **Fix F1 before merging**: P1 ghost popup. Trivial one-line fix in `hotReload` — can be done in-session
  without a full task dispatch.
- **F2-F4**: Non-blocking hygiene. Defer to a polish pass or fix alongside F1.
- **After F1 fix**: Run `swift test` (116/116), then manual smoke: copy text → see popup → open settings
  → change popup style → save → verify old popup dismissed + next translation shows new style.

## Vendor output (parsed)

```
I see the task — T-MAC-REV: adversarial review of Fix #1+Fix #2 (diff `1d913ea` vs `729e68d`). Let me pull the diff and understand the codebase context.Now let me read the current state of the source files at HEAD (`1d913ea`):Let me also verify the retrospective doc exists at HEAD and run the tests:All 116 tests pass. Now let me do a deeper review of the actual logic around the fixes. Let me check a few more things:Let me verify the `static func main()` pattern exists at `729e68d` (the app startup fix):Good. Now I have the complete picture. Let me check the remaining SettingsWindow diff:Now I have the full picture. Let me verify one more potential issue — the popup cleanup when `hotReload` replaces it:I've now fully analyzed the diff and the current state. Let me write the review findings document. Key finding: old popup not dismissed on hotReload replacement.Now let me write the review output:<thinking>There's already a T-MAC-REV-output.md. Let me read it to see if this task was already done.</thinking>The existing output.md is just a placeholder stub from the background task dispatch. I'll write the actual review findings now.<thinking>Now I need to update queue.md to mark T-MAC-REV as done. Let me do that.</thinking>
Now update queue.md status for T-MAC-REV:<thinking>Now let me verify the checks from the output document — `git diff --name-only` should show only the review file and queue.md:</thinking><thinking>The output file was written but not tracked by git. It's a new file. Let me check git status to see what's going on:</thinking>
Wait, the handoffs output file isn't showing in diff. Let me check:<thinking>T-MAC-REV-output.md is untracked (`??`) and queue.md is modified. Both are expected changes from this review task. The output file is new (it existed before but as a placeholder that might have been gitignored), and queue.md has the status flip. These are the only artifacts touched — no product code was edited. ✅

The `git diff --name-only` shows only `.hopper/queue.md` because the output file is untracked (not in git yet), so diff doesn't show it. With `git status`, both files show up. This is fine.

Now let me add an activity log entry to queue.md and finalize.</thinking>
Good — only the review artifact and queue.md status flip were touched. No product code modified.**T-MAC-REV adversarial review complete. Verdict: PASS_WITH_CHANGES.**

**4 findings across 4 files (1353 LOC):**

| ID | Severity | Summary |
|---|---|---|
| F1 | **P1** | `hotReload` replaces popup without dismissing old visible window → ghost popup (permanent if `autoDismissSeconds == 0`) |
| F2 | P2 | Redundant `setActivationPolicy(.accessory)` called in both `main()` and `applicationDidFinishLaunching` |
| F3 | P2 | `if window == nil` guard in `show()` is structurally dead code (always true with fresh controller) |
| F4 | P2 | `openSettings` can produce dual settings windows if triggered from tray while settings already open |

**Verified:**
- `swift test`: 116/116 green (no regression)
- `swift build`: clean
- Settings save effect: hotReload covers all components (pipeline + hotkey + clipboard + popup + login) ✅
- GroupBox native styling: CardView uses native GroupBox, `.primary` colors ✅
- `static func main()` app-launch fix preserved from `729e68d` ✅

**Recommendation:** Fix F1 (one-line `popup?.dismiss()` in `hotReload`) before merging. F2-F4 are P2 hygiene.
```

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 390247
- end_time: 2026-06-18T09:56:44.778Z
- log: see `T-MAC-REV-output.log` for raw output

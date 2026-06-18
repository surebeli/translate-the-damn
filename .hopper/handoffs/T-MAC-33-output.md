---
task_id: T-MAC-33
adapter: kimi
model: (vendor default)
status: failed
pid: null
start_time: "2026-06-18T05:48:27.927Z"
end_time: "2026-06-18T05:55:15.658Z"
exit_code: 0
duration_ms: 407687
mode: foreground
phase: failed
last_progress_at: "2026-06-18T05:50:46.000Z"
last_progress: swift build + swift test passed (71 tests, 0 failures).
progress_seq: 2
progress_log: ./T-MAC-33-progress.log
raw_log: ./T-MAC-33-output.log
vendor_session_id: null
terminal_event_emitted: true
host_native: true
session_id: null
log: ./T-MAC-33-output.log
started_by_pid: 51093
signal: null
timed_out: null
adapter_status: permission-fail
---

# T-MAC-33 — Menu-bar tray for macOS

## Summary
Implemented the macOS menu-bar tray (`NSStatusItem`) per spec §3. `TrayController` creates a square-length status item with a template SF Symbol (`character`, fallback to a drawn "文" glyph), shows a tooltip that switches between `tray.tooltip.listening` and `tray.tooltip.paused`, and exposes a menu with 监听剪贴板 (toggle checkmark), 打开设置… (callback), and 退出 (`NSApp.terminate`). The controller owns the global listen switch: toggling updates `isListeningOn`, persists to `config.general.listenClipboard` via `ConfigService.save`, and starts/stops the injected `ClipboardWatcher`. `AppDelegate` wires the tray on launch and routes the toggle-listen hotkey through the tray so persistence, UI, and watcher state stay synchronized.

## Files touched

| Path | Δ lines | Purpose |
|------|---------|---------|
| `platforms/macos/src/App/TrayController.swift` | +138 | New tray controller: `NSStatusItem`, tooltip, menu, global listen switch, persistence, watcher control. |
| `platforms/macos/src/App/AppDelegate.swift` | +69/-2 | Create `TrayController` on launch; route hotkey toggle through tray; add `@MainActor`; add `openSettings()` stub. |

## Acceptance verification (6/6)

- **`TrayController` creates `NSStatusItem` with `.squareLength` and template image**
  - ✓ `grep -n "statusItem(withLength: NSStatusItem.squareLength)" platforms/macos/src/App/TrayController.swift`
  - Evidence: line 34 creates the status item; `makeTemplateImage()` sets `image.isTemplate = true` (lines 116/135) and uses SF Symbol `character` with "文" fallback.

- **Tooltip switches between `tray.tooltip.listening` and `tray.tooltip.paused`**
  - ✓ `grep -n "tray.tooltip" platforms/macos/src/App/TrayController.swift`
  - Evidence: lines 78-79 set `statusItem.button?.toolTip` to `StringsLoader["tray.tooltip.listening"]` when on, `StringsLoader["tray.tooltip.paused"]` when off.

- **Menu has 监听剪贴板 toggle (checkmark), 打开设置… callback, 退出 (`NSApp.terminate`) from strings**
  - ✓ `grep -n "tray.menu" platforms/macos/src/App/TrayController.swift`
  - Evidence: lines 36, 41, 46, 55 build the menu from `StringsLoader["tray.menu.listen"]`/`settings`/`exit`; `listenMenuItem.state` toggles `.on`/`.off` (line 76); exit action calls `NSApp.terminate(sender)` (line 107).

- **Global switch `isListeningOn` persists to `config.general.listenClipboard` and starts/stops `ClipboardWatcher`**
  - ✓ `grep -n "persistListeningState\|watcher.start\|watcher.stop" platforms/macos/src/App/TrayController.swift`
  - Evidence: `setListening(_:)` (line 69) calls `updateState(to:persist:)`; `persistListeningState(on:)` (line 92) loads config, sets `general.listenClipboard`, and saves; `updateState` calls `watcher.start()`/`watcher.stop()` (lines 82/84).

- **Wired into `AppDelegate` on launch; toggle callback starts/stops watcher + persists**
  - ✓ `grep -n "TrayController" platforms/macos/src/App/AppDelegate.swift`
  - Evidence: lines 11, 32-37 instantiate `TrayController` in `applicationDidFinishLaunching`; `onToggleListenHotkey()` (line 86) routes through `tray.setListening(!tray.isListeningOn)`.

- **`swift build` succeeds; `swift test` green (no regression)**
  - ✓ `swift build` completed successfully (0.80s).
  - ✓ `swift test` executed 71 tests with 0 failures.

## Decisions / deviations from spec

- 无偏离

## Open questions for Leader

- none

## Commit

`d9925e0` "[T-MAC-33] Implement macOS menu-bar tray with global listen switch"

## Checks

- `git diff --check d9925e0^ d9925e0 -- platforms/macos/src/App/AppDelegate.swift platforms/macos/src/App/TrayController.swift` → clean (no whitespace errors).
- `swift build` → Build complete! (0.80s)
- `swift test` → Executed 71 tests, with 0 failures

## Next recommendation

Per MANIFEST.md cursor, the next macOS task is the settings window / popup polish (T-MAC-34 area). The tray's `openSettings` callback is already wired to `AppDelegate.openSettings()` as a stub ready for the settings window implementation.

## Vendor output (parsed)

_(vendor produced no parsed text; see `T-MAC-33-output.log` for the raw output stream.)_

## Status (background completion)
- queue_status: failed
- adapter_status: permission-fail
- exit_code: 0
- duration_ms: 407687
- end_time: 2026-06-18T05:55:15.658Z

### Adapter error
```
kimi binary not found in PATH. Install: curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash (Windows: irm https://code.kimi.com/kimi-code/install.ps1 | iex; Homebrew: brew install kimi-code).
```
- log: see `T-MAC-33-output.log` for raw output

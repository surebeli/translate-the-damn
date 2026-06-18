# Porting guide — macOS (Apple Silicon)

Reference for a fresh session bringing **translate-the-damn** to macOS. Read the design spec first
(`docs/superpowers/specs/2026-06-17-translate-the-damn-design.md`); this doc only covers the
platform delta. The product behaviour (dual trigger, 6 backends, acrylic popup, tray, settings,
config.json) is unchanged — only the OS-facing layer is rewritten.

## Scope (this round)

- **Apple Silicon only** (arm64). Build/ship arm64 exclusively — no Intel/Universal, no Rosetta.
- Suggested minimum: **macOS 14 (Sonoma)** — modern materials, `SMAppService` login items, stable
  SwiftUI/AppKit. (Apple Silicon hardware is macOS 11+, but target 14+ to avoid back-compat work.)
- Desktop menu-bar app, no Dock-only window (mirrors the Windows tray app).

## What carries over vs what's rewritten

- **Reuse as-is:** the entire `TranslateTheDamn.Core` project — models, `ConfigService`,
  `TranslatorRegistry`, all 6 backend adapters, `TranslationPipeline`, `PromptBuilder`,
  `AnsiStripper`, `ProcessRunner`, `HotkeyParser`. It is plain `net9.0` and platform-agnostic. The
  agent-CLI commands and the two HTTP request shapes are identical on macOS.
- **Rewrite:** everything in `TranslateTheDamn.App` (WPF + WinForms + Win32 P/Invoke). This is the
  whole porting effort.

## Strategy — native Swift (chosen)

**Chosen: native Swift (SwiftUI + AppKit).** Mandated by `CONSTITUTION.md` line 7 (macOS = Swift)
and the "same behaviour, each platform's native skin" principle (Law 5): best-fit permissions,
materials and menu-bar ergonomics. The trade-off is re-implementing the backend layer in Swift
(Process spawning, HTTP, config, the manifest interpreter) rather than reusing the .NET `Core` — but
the backend layer is now **declarative data** (`spec/backends.json`) read by a generic Swift
interpreter, so the re-implementation is "interpret the manifest + satisfy the `conformance/`
vectors", not "re-derive 6 backends from scratch". The Windows `Core` stays the behavioural
reference; the Swift port is verified against the same `conformance/` golden vectors (Law 2), not by
sharing code.

> Previously this section recommended .NET 9 + Avalonia (reuse `Core`). That drifted from the
> Constitution's macOS = Swift declaration; corrected 2026-06-18. The Windows→macOS API mapping
> table below applies regardless of language. (The "Core adaptation checklist" further down is
> framed for the Avalonia/reuse path; its concepts — POSIX execute-bit, knownInstallPaths,
> login-shell PATH, config path, neutral sandbox CWD — transfer to the Swift `PathResolver` /
> `ProcessRunner` natively.)

## Platform boundary map (Windows → macOS)

| Concern | Windows (current) | macOS equivalent |
|---|---|---|
| Clipboard watch | `AddClipboardFormatListener` (event) | **No change event exists** — poll `NSPasteboard.general.changeCount` on a timer (~250ms). This is the biggest behavioural delta. |
| Global hotkey | `RegisterHotKey` + WM_HOTKEY | Carbon **`RegisterEventHotKey`** (preferred — needs **no** accessibility permission) or `NSEvent.addGlobalMonitorForEvents` (needs Input-Monitoring permission). Avalonia: P/Invoke Carbon. |
| No-focus-steal popup | `WS_EX_NOACTIVATE` + topmost | `NSPanel` with `.nonactivatingPanel` style mask + `.floating`/`.statusBar` window level + `hidesOnDeactivate=false`. Avalonia: borderless `Window` + `ShowActivated=false` + interop to set the panel style. |
| Acrylic / Mica | DWM `SetWindowCompositionAttribute` / `DWMWA_SYSTEMBACKDROP_TYPE` | `NSVisualEffectView` (material `.hudWindow`/`.popover`, `.behindWindow` blending). Avalonia: `TransparencyLevelHint="AcrylicBlur"` (maps to vibrancy on macOS). |
| Tray icon | WinForms `NotifyIcon` | `NSStatusItem` (menu-bar extra). Avalonia: `TrayIcon` (supported on macOS). |
| Window/exe icon | `<ApplicationIcon>app.ico` | `.icns` in the app bundle `Info.plist` (`CFBundleIconFile`); generate from the same glyph via `iconutil`. |
| Start at login | HKCU `...\Run` | `SMAppService.mainApp.register()` (macOS 13+) or a LaunchAgent plist. |
| Kill process tree | `taskkill /T /F` | `Process.Kill(entireProcessTree:true)` already works on macOS in `ProcessRunner` (the Windows-only `taskkill` branch is skipped). Verify against the node-based CLIs. |
| DPI / manifest | `app.manifest` PerMonitorV2 | N/A — Cocoa is point-based/Retina-aware automatically. Drop the manifest. |

## Core adaptation checklist (small, in the shared project)

1. **`PathResolver` POSIX branch** currently only does `File.Exists` — add an **execute-bit check**
   (`access(path, X_OK)` / `UnixFileMode` has `UserExecute`). Also the `.cmd/.ps1` wrapping is
   Windows-only (POSIX returns the binary directly — already correct).
2. **GUI PATH gotcha (critical).** A macOS app launched from Finder gets a **minimal PATH**
   (`/usr/bin:/bin:/usr/sbin:/sbin`) — it does **not** inherit the shell PATH, so `claude`/`codex`
   etc. installed under Homebrew or nvm **won't be found**. Fix by giving `PathResolver` macOS
   `knownInstallPaths`/extra search dirs: `/opt/homebrew/bin` (Apple Silicon Homebrew),
   `/usr/local/bin`, `~/.npm-global/bin`, `~/.nvm/versions/node/*/bin`, `~/.local/bin`, and/or read
   the login shell's PATH (`zsh -ilc 'echo $PATH'`) once at startup. Make this injectable per-OS.
3. **agy `knownInstallPaths`** is currently the Windows `%LOCALAPPDATA%\agy\bin\agy.exe`. Find the
   macOS install location (research item) and add it.
4. **`Sandbox.Directory`** (neutral CWD) — uses `LocalApplicationData`, which resolves on macOS to
   `~/.config` (or `~/Library/Application Support` depending on runtime); fine, just confirm it's an
   empty dir.
5. Config path: spec uses `%USERPROFILE%\.translatethedamn\config.json`; on macOS
   `Environment.SpecialFolder.UserProfile` → `~`, so it lands at `~/.translatethedamn/config.json`.
   Decide whether to keep that or move to `~/Library/Application Support/translate-the-damn/`.

## macOS-specific gotchas / permissions

- **Prefer Carbon `RegisterEventHotKey`** for the global hotkey — it works with **no TCC prompt**.
  `CGEventTap`/global `NSEvent` monitors require Accessibility/Input-Monitoring permission (a prompt
  + System Settings round-trip); avoid unless you need richer key handling.
- **Code signing + notarization + hardened runtime** are required to distribute outside the App Store
  (Gatekeeper). Spawning child processes is fine under hardened runtime without extra entitlements.
- Do **not** ship as a sandboxed App Store app: the App Sandbox would block spawning the user's CLIs.

## Open research items (confirm before/at dev)

- Exact install paths + whether **agy** ships for macOS at all (and whether `gemini` is the better
  default fallback there).
- Best login-shell PATH-resolution approach vs. a curated known-dirs list.
- Avalonia vibrancy fidelity for the popup vs. dropping to a translucent solid card.
- Avalonia global-hotkey interop snippet (Carbon) — small native shim.

## Backends on macOS (unchanged logic, verify availability)

The adapter argv/stdin/HTTP bodies are identical. Re-run a live smoke test per backend on the Mac
(`--live <backend>` harness already exists) once PATH resolution is fixed, since "found on PATH" is
the main thing that changes.

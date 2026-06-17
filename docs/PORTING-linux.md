# Porting guide — Linux (Ubuntu desktop)

Reference for a future Linux port of **translate-the-damn**. Read the design spec
(`docs/superpowers/specs/2026-06-17-translate-the-damn-design.md`) and `PORTING-macos.md` first —
the Core-reuse strategy is the same. **This round is documentation only: do NOT build the Linux
version yet.** Several platform questions (below) must be confirmed before any implementation.

## Scope (tentative, this round)

- **Ubuntu 24.04 LTS or newer, desktop edition only.** No server, no other distros committed yet.
- Note: Ubuntu 24.04 ships **GNOME on Wayland by default** (X11 session still selectable). The
  Wayland default is the single biggest risk to this product's core mechanics (see open questions).
- Apple-Silicon-style narrowing doesn't apply; target x86-64 first, arm64 later if needed.

## What carries over

Same as macOS: **reuse `TranslateTheDamn.Core` unchanged** (net9.0, platform-agnostic — backends,
config, pipeline, path resolution, prompt). Only the OS-facing `App` layer is new. The POSIX
adaptation items in `PORTING-macos.md` (`PathResolver` execute-bit + known dirs, kill-tree already
works, config path under `~`) apply equally on Linux.

## Tentative strategy

**.NET 9 + Avalonia, reuse Core** (strongly favoured — Avalonia's best-supported desktop target is
Linux/X11). A native GTK rewrite is possible but loses Core reuse; not recommended.

## Platform boundary map (Windows → Linux) — to be validated

| Concern | Windows (current) | Linux (X11 / Wayland) |
|---|---|---|
| Clipboard watch | `AddClipboardFormatListener` | **X11:** poll/own the CLIPBOARD selection (xfixes selection-notify) or poll via `wl-clipboard`. **Wayland:** no general clipboard-change API for background apps — restricted by design; likely poll via the clipboard portal. **Needs confirmation.** |
| Global hotkey | `RegisterHotKey` | **X11:** `XGrabKey` works. **Wayland:** global hotkeys are intentionally restricted; depends on the compositor — GNOME exposes custom shortcuts via its settings/D-Bus, and the `GlobalShortcuts` XDG portal exists but support is uneven. **Biggest open question.** |
| Tray icon | WinForms `NotifyIcon` | `StatusNotifierItem` (KDE/AppIndicator spec) via libayatana-appindicator. **GNOME removed legacy tray** — requires the user to have the *AppIndicator/KStatusNotifier* GNOME extension. Avalonia `TrayIcon` uses SNI. **Confirm GNOME has the extension or document the dependency.** |
| No-focus-steal popup | `WS_EX_NOACTIVATE` | X11: `_NET_WM_STATE_ABOVE` + `_NET_WM_WINDOW_TYPE_UTILITY/NOTIFICATION` + not taking input focus. Wayland: layer-shell (`wlr-layer-shell`) gives overlay/no-focus surfaces but **GNOME/Mutter does not implement layer-shell** — placement + no-activate is harder on GNOME Wayland. |
| Acrylic / blur | DWM backdrop | Compositor-dependent and often unavailable; **plan to fall back to a translucent solid card** (the popup already supports a `solid` style). |
| Window/app icon | `<ApplicationIcon>` | PNG hicolor icons + a `.desktop` file with `Icon=`. |
| Start at login | HKCU Run key | `~/.config/autostart/translate-the-damn.desktop`. |

## Packaging caveat (important)

This app **spawns the user's host CLIs** (`claude`, `codex`, …). **Flatpak and Snap run sandboxed**
and cannot see/spawn host binaries by default — packaging as Flatpak/Snap would break every CLI
backend unless using host-spawn portals. **Prefer a `.deb` or `AppImage`** (non-sandboxed) so
spawning host CLIs and reading `~/.config` work normally. Confirm before choosing a package format.

## Open questions to resolve BEFORE development

1. **Wayland vs X11 support matrix.** Decide whether v1 Linux targets X11 only (much simpler:
   XGrabKey + xfixes clipboard + working tray/placement) and treats Wayland as best-effort/later, or
   commits to Wayland. This decision gates almost everything below.
2. **Global hotkey on Wayland** — is the XDG `GlobalShortcuts` portal viable on Ubuntu 24.04 GNOME,
   or do we require X11 / a GNOME shortcut registration?
3. **Clipboard-change detection on Wayland** without focus — feasible via portal/polling? Latency?
4. **Tray** — depend on the GNOME AppIndicator extension, or document it as a prerequisite?
5. **No-focus-steal overlay placement** on GNOME Wayland (no layer-shell) — acceptable fallback?
6. **Packaging** — `.deb` vs `AppImage`; confirm host CLI spawning works in the chosen format.
7. **CLI install paths** on Ubuntu (npm global, nvm, snap-installed tools) for `PathResolver`
   known-dirs; plus the GUI-PATH-inheritance question (less severe than macOS but verify under the
   `.desktop` launch).

Until 1–6 are answered, treat the table above as provisional.

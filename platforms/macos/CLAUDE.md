# CLAUDE.md — macOS platform

Obey the root **[/CONSTITUTION.md](../../CONSTITUTION.md)** (laws + pointer map to spec /
conformance / backend manifest / strings / parity). This file holds **macOS-only** notes.

- Stack: **Swift** (SwiftUI + AppKit). Apple Silicon only (arm64). Minimum macOS 14 (Sonoma).
- Native per Constitution line 7: no shared UI/runtime code with Windows. Parity is enforced by
  `conformance/` vectors + `PARITY.md`, not by shared binaries.
- Backend calls MUST read `spec/backends.json` (declarative manifest) via a generic interpreter —
  never hardcode backends. UI strings read `strings/zh-CN.json`.
- Build/test: `swift build` / `swift test` (the conformance runner walks up to repo-root `conformance/`).
- macOS specifics: clipboard = poll `NSPasteboard.general.changeCount` (~250ms — no change event);
  global hotkey = Carbon `RegisterEventHotKey` (preferred — no TCC prompt); popup = `NSPanel`
  (nonactivatingPanel + floating level) + `NSVisualEffectView`; tray = `NSStatusItem`; settings =
  SwiftUI; start-at-login = `SMAppService`; app icon = `.icns` via `iconutil`.
- GUI PATH gotcha: an app launched from Finder gets a minimal PATH → `PathResolver` must add
  `/opt/homebrew/bin`, `~/.nvm/versions/node/*/bin`, `~/.local/bin`, `~/.kimi-code/bin`,
  `~/.grok/bin` and/or read the login-shell PATH (`zsh -ilc 'echo $PATH'`) once at startup.
- Do NOT enable App Sandbox (it would block spawning the user's CLIs). arm64 only; sign + notarize +
  hardened runtime for distribution.
- Orchestration: this port is built via hopper vendors + subagents from the main session. See
  `.hopper/queue.md`, `.hopper/AGENTS.md`, `.hopper/MANIFEST.md`, `.hopper/COST-LOG.md`.

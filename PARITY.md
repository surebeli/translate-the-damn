# PARITY — feature × platform status

The cross-environment to-do board (Constitution Law 3). A feature is "done" on a platform only when
its **spec entry exists** AND — for logic — its **conformance vector passes on that platform's CI**.
UI/interaction items are verified against the interaction spec + a per-platform UI check.

Legend: ✅ shipped · 🚧 in progress · ⬜ not started · ⚠️ partial/best-effort · — n/a

| Feature | Spec | Conformance | Win | macOS | Linux |
|---|---|---|---|---|---|
| Clipboard watch (toggle, self-write guard) | §4, §4.1 | — (UI/OS) | ✅ | ⬜ | ⬜ |
| Global hotkey (configurable, conflict-detect) | §4 | `hotkey-parser` | ✅ | ⬜ | ⬜ |
| Translation rules / prompt building | §5 | `prompt-builder` | ✅ | ⬜ | ⬜ |
| ANSI output cleaning | §6 | `ansi-stripper` | ✅ | ⬜ | ⬜ |
| Backends — claude, codex (CLI) | §6 | `spec/backends.json` | ✅ | ⬜ | ⬜ |
| Backends — copilot, agy (CLI) | §6 | `spec/backends.json` | ⚠️ | ⬜ | ⬜ |
| Backends — google-v2, doubao (HTTP) | §6.1/6.2 | `spec/backends.json` | ✅ | ⬜ | ⬜ |
| Last-translation cache (text+backend+model) | §4.1 | _(vector TODO)_ | ✅ | ⬜ | ⬜ |
| config.json bootstrap / read / write | §7 | _(vector TODO)_ | ✅ | ⬜ | ⬜ |
| Acrylic popup (no-focus-steal, hover-keep, auto-dismiss, scroll) | §8 | — (UI) | ✅ | ⬜ | ⬜ |
| Popup copy + close buttons | §8 | — (UI) | ✅ | ⬜ | ⬜ |
| Settings window (backend/model, fields, live hotkey check) | §9 | — (UI) | ✅ | ⬜ | ⬜ |
| Tray icon + global switch (persisted) | §3 | — (UI) | ✅ | ⬜ | ⬜ |
| App icon = tray glyph (single source) | — | — (UI) | ✅ | ⬜ | ⬜ |
| Dark scrollbar theme | — | — (UI) | ✅ | ⬜ | ⬜ |

## Version

| | Win | macOS | Linux |
|---|---|---|---|
| App version | **0.2.0** | — | — |
| config schema | 1 | — | — |

## Notes

- ⚠️ copilot/agy on Windows are best-effort (known Windows `-p` quirks; agy falls back to gemini).
- "vector TODO" = logic that is shipped on Windows but not yet extracted into a language-neutral
  conformance vector; do that before the macOS port so the Mac column has a test to satisfy.
- The Windows adapters currently **hardcode** the backend definitions that `spec/backends.json`
  declares; refactoring Windows to read the manifest is a tracked future task (keeps the manifest
  the single source for all platforms).

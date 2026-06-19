# PARITY — feature × platform status

The cross-environment to-do board (Constitution Law 3). A feature is "done" on a platform only when
its **spec entry exists** AND — for logic — its **conformance vector passes on that platform's CI**.
UI/interaction items are verified against the interaction spec + a per-platform UI check.

Legend: ✅ shipped · 🚧 in progress · ⬜ not started · ⚠️ partial/best-effort · — n/a

| Feature | Spec | Conformance | Win | macOS | Linux |
|---|---|---|---|---|---|
| Clipboard watch (toggle, self-write guard) | §4, §4.1 | — (UI/OS) | ✅ | 🚧 | ⬜ |
| Global hotkey (configurable, conflict-detect) | §4 | `hotkey-parser` | ✅ | ✅ | ⬜ |
| Translation rules / prompt building | §5 | `prompt-builder` | ✅ | ✅ | ⬜ |
| ANSI output cleaning | §6 | `ansi-stripper` | ✅ | ✅ | ⬜ |
| Backends — claude, codex (CLI) | §6 | `spec/backends.json` | ✅ | ✅ | ⬜ |
| Backends — copilot, agy (CLI) | §6 | `spec/backends.json` | ⚠️ | ⚠️ | ⬜ |
| Backends — google-v2, doubao (HTTP) | §6.1/6.2 | `backend-requests` + `spec/backends.json` | ✅ | ✅ | ⬜ |
| Last-translation cache (text+backend+model) | §4.1 | `pipeline-cache` | ✅ | ✅ | ⬜ |
| config.json defaults / bootstrap | §7 | `config-defaults` | ✅ | ✅ | ⬜ |
| Acrylic popup (no-focus-steal, hover-keep, auto-dismiss, scroll) | §8 | — (UI) | ✅ | 🚧 | ⬜ |
| Popup copy + close buttons | §8 | — (UI) | ✅ | 🚧 | ⬜ |
| Settings window (backend/model, fields, live hotkey check) | §9 | — (UI) | ✅ | 🚧 | ⬜ |
| Tray icon + global switch (persisted) | §3 | — (UI) | ✅ | 🚧 | ⬜ |
| App icon = tray glyph (single source) | — | — (UI) | ✅ | 🚧 | ⬜ |
| Dark scrollbar theme | — | — (UI) | ✅ | 🚧 | ⬜ |

## Version

| | Win | macOS | Linux |
|---|---|---|---|
| App version | **0.2.0** | **0.2.0** (target — `CFBundleShortVersionString` via T-MAC-51 Info.plist) | — |
| config schema | 1 | 1 | — |

## Notes

- ⚠️ copilot/agy on Windows are best-effort (known Windows `-p` quirks; agy falls back to gemini).
- Conformance coverage: `prompt-builder`, `ansi-stripper`, `hotkey-parser`, `config-defaults`,
  `backend-requests` (google-v2 + doubao request shapes), `pipeline-cache` — all run on Windows CI
  (150 tests). macOS/Linux add a runner over the same JSON.
- The Windows adapters currently **hardcode** the backend definitions that `spec/backends.json`
  declares; refactoring Windows to read the manifest is a tracked future task (keeps the manifest
  the single source for all platforms).
- **macOS UI consolidated to a single style.** The macOS port experimented with 7 swappable UI
  styles (`uiStyle` switch); it has been consolidated to one finalized "clean" UI (single-page
  grouped Form settings + clean glass-card popup with italic source). The `uiStyle` switch, picker,
  and the other six style implementations were removed. This was macOS-only (never a shared feature),
  so it is not a parity item; `config.general.uiStyle` stays in the schema (nil-default) for
  back-compat. Decision rationale: the UI-style review on branch `expe/202606`.

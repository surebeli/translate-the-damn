# Build progress — translate-the-damn MVP

Autonomous build log. Branch `feat/mvp-client`. Spec: `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md`.

## Status: MVP complete ✅

All phases done. Solution builds clean (Debug + Release). 83 offline tests green. claude + codex
verified live (real translations). Google/Doubao request+parse unit-verified (need a key to run).

- [x] P0 — Environment + scaffold (.NET 9: Core / App(WPF+WinForms) / Tests; offline + no-NuGet)
- [x] P1 — Core models, ConfigService (bootstrap), PathResolver, PromptBuilder, AnsiStripper (+ tests)
- [x] P2 — 6 backends: ProcessTranslator (claude/codex/copilot/agy) + HttpTranslator (google-v2/doubao) (+ tests)
- [x] P3 — TranslationPipeline (filter/dedupe/supersede) + ProcessRunner (timeout/kill-tree) (+ tests)
- [x] P4 — Tray icon + global switch (persisted) + AppController composition root
- [x] P5 — ClipboardListener (self-write guard) + HotkeyService (RegisterHotKey + conflict) + message window
- [x] P6 — PopupWindow (no-focus-steal, acrylic, source+translation, copy, hover-keep, auto-dismiss)
- [x] P7 — SettingsWindow (backend→model catalog, per-backend fields, live hotkey check) → config.json + hot-reload
- [x] P8 — Live end-to-end fixes (stdin prompt, neutral sandbox CWD), README, Release build, final commit

## Verified

- Build: `dotnet build TranslateTheDamn.sln` (Debug + Release) clean.
- Tests: `dotnet run --project tests\TranslateTheDamn.Tests` → 83 passed.
- App: launches to tray, bootstraps `%USERPROFILE%\.translatethedamn\config.json` (clean, Chinese unescaped).
- Live: `--live claude` and `--live codex` both return correct translations end-to-end.

## Polish round (post-MVP, requested)

- [x] Custom dark thin scrollbar (`UI/Theme.xaml`, app-wide ScrollBar ControlTemplate) replacing the
      classic gray Win32 scrollbar — needed a custom template (no NuGet theme lib).
- [x] Popup translation now scrollable (ScrollViewer + dark scrollbar + wheel handler that works
      while the popup is non-focus-stealing).
- [x] Settings window title-bar icon unified with the tray glyph (`UI/AppIcon.cs`, single source for both).

## Backend status (see README for detail)

claude ✅live · codex ✅live · google-v2 ✅unit (needs key) · doubao ⚠️unit (confirm with real ARK key)
· copilot ⚠️best-effort (GitHub token; Win #1181) · agy ⚠️best-effort (Win #27466; gemini fallback)

## For the user (usage phase)

- Open Settings → fill google/doubao API keys to use the fast HTTP backends.
- Live-test copilot/agy (need auth; both have known Windows `-p` quirks — agy falls back to gemini).
- Confirm the doubao request shape with a real ARK key (official docs were JS-rendered → medium confidence).
- Default backend is `claude`; switch in Settings. Default hotkey Ctrl+Alt+T.

## Notable engineering decisions

- Zero external NuGet (sandbox blocks nuget.org) → framework-only + a dependency-free test harness.
- CLI prompts go via stdin (cmd.exe mangles multi-line/Chinese args); CLIs spawn from an empty
  sandbox dir so they don't load the current project's CLAUDE.md/MCP/hooks.
- One adapter contract (ported from hopper-plugin's VendorAdapter) over two families: ProcessTranslator / HttpTranslator.

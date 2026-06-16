# Build progress — translate-the-damn MVP

Autonomous build log. Branch `feat/mvp-client`. Spec: `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md`.

## Phases

- [x] P0 — Environment + scaffold (.NET 9 solution: Core / App(WPF+WinForms) / Tests; offline build verified; no-NuGet constraint)
- [x] P0 — Design spec + this tracker committed
- [x] P1 — Core models, ConfigService (config.json bootstrap), PathResolver, PromptBuilder, AnsiStripper (+ tests)
- [x] P2 — Backends: ProcessTranslator (claude/codex/copilot/agy) + HttpTranslator (google-v2/doubao) + registry (+ tests)
- [x] P3 — TranslationPipeline (filter/dedupe/supersede) + ProcessRunner (timeout/kill-tree) (+ tests)  ·  **74 tests green**
- [x] P4 — App shell: tray icon + global switch (persisted) + AppController composition root
- [x] P5 — ClipboardListener (AddClipboardFormatListener + self-write guard) + HotkeyService (RegisterHotKey + conflict) + hidden message window
- [x] P6 — PopupWindow (WS_EX_NOACTIVATE no-focus-steal, acrylic blur, original+translation, copy, hover-keep, auto-dismiss, top-centre)
- [x] P7 — SettingsWindow (dark/Mica, backend→model combobox from catalog, per-backend fields, auth hint, live hotkey check) → writes config.json + hot-reload
- [x] P8a — Full solution builds clean; app launches without crash; first-run config.json bootstrap verified (clean, Chinese unescaped)
- [ ] P8 — README + final polish + final commit

## Test coverage so far (dependency-free harness, `dotnet run` in tests/)

ConfigService bootstrap/round-trip/corrupt-recovery/Chinese-unescaped · PathResolver PATH/known-paths/.cmd-wrap/qualified ·
PromptBuilder · AnsiStripper · every CLI adapter argv (claude/codex/copilot/agy) · google-v2 & doubao request bodies +
response parsing (incl. doubao reasoning-item-before-message) · HTTP credential gating · registry · pipeline filter/dedupe/route.

## Notes / decisions baked in

- Windows 11 only, .NET 9, C#. WPF + WinForms tray. Zero external NuGet (nuget.org blocked) → framework-only + custom test harness.
- 6 backends. CLI ones tamed into clean text→text (light model, no approvals, empty stdin, strip ANSI).
- config.json at `%USERPROFILE%\.translatethedamn\config.json`; first-run hardcoded bootstrap; UI reads/writes it.
- Dual trigger: clipboard watcher (toggleable) + global hotkey (translates current clipboard).

## For the user (usage phase, not blockers)

- Fill google/doubao API keys in settings.
- Live smoke-test copilot/agy on this machine (both have Windows `-p` no-output bug reports; agy has gemini fallback + log diagnosis).
- Confirm doubao request shape with a real ARK key (official docs were JS-rendered; medium confidence).

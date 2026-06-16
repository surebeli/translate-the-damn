# Build progress — translate-the-damn MVP

Autonomous build log. Branch `feat/mvp-client`. Spec: `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md`.

## Phases

- [x] P0 — Environment + scaffold (.NET 9 solution: Core / App(WPF+WinForms) / Tests; offline build verified; no-NuGet constraint)
- [x] P0 — Design spec + this tracker committed
- [ ] P1 — Core models, ConfigService (config.json bootstrap), PathResolver, PromptBuilder + tests
- [ ] P2 — Backends: ProcessTranslator (claude/codex/copilot/agy) + HttpTranslator (google-v2/doubao) + registry + tests
- [ ] P3 — TranslationPipeline (filter/dedupe/debounce/supersede, self-write guard, timeouts)
- [ ] P4 — App shell: tray icon + global switch (persisted)
- [ ] P5 — ClipboardListener (AddClipboardFormatListener) + HotkeyService (RegisterHotKey + conflict)
- [ ] P6 — PopupWindow (no-focus-steal, acrylic, original+translation, copy, hover-keep, auto-dismiss)
- [ ] P7 — SettingsWindow (Mica, backend/model combobox, auth lamp, fields) → writes config.json + hot-reload
- [ ] P8 — Full build green, tests green, README, final commit

## Notes / decisions baked in

- Windows 11 only, .NET 9, C#. WPF + WinForms tray. Zero external NuGet (nuget.org blocked) → framework-only + custom test harness.
- 6 backends. CLI ones tamed into clean text→text (light model, no approvals, empty stdin, strip ANSI).
- config.json at `%USERPROFILE%\.translatethedamn\config.json`; first-run hardcoded bootstrap; UI reads/writes it.
- Dual trigger: clipboard watcher (toggleable) + global hotkey (translates current clipboard).

## For the user (usage phase, not blockers)

- Fill google/doubao API keys in settings.
- Live smoke-test copilot/agy on this machine (both have Windows `-p` no-output bug reports; agy has gemini fallback + log diagnosis).
- Confirm doubao request shape with a real ARK key (official docs were JS-rendered; medium confidence).

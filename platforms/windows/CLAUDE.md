# CLAUDE.md — Windows platform

Obey the root **[/CONSTITUTION.md](../../CONSTITUTION.md)** (laws + pointer map to spec /
conformance / backend manifest / strings / parity). This file holds **Windows-only** notes.

- Stack: .NET 9, C#, WPF + WinForms (tray). Solution: `TranslateTheDamn.sln` (Core + App + Tests).
- Build: `dotnet build platforms/windows/TranslateTheDamn.sln -c Release`
- Tests + shared conformance vectors: `dotnet run --project platforms/windows/tests/TranslateTheDamn.Tests`
  (the harness walks up to the repo-root `conformance/`). `-- --live <backend>` for a real CLI smoke test.
- Zero external NuGet (framework-only); dependency-free test harness.
- Windows specifics: CLI prompts go via **stdin** (cmd.exe mangles multi-line/Chinese args); CLIs are
  spawned from a neutral **sandbox CWD** so they don't load the current project; acrylic via DWM;
  global hotkey via `RegisterHotKey`; tray via WinForms `NotifyIcon`.
- **Q2 in progress:** the backend adapters here still hardcode what `spec/backends.json` declares;
  refactoring them to read the manifest is tracked in `PARITY.md`.

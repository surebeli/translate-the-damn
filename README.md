# translate-the-damn

A lightweight **Windows 11** "copy / hotkey → translate" tool for heavy LLM users. It watches the
clipboard (toggleable) and a configurable global hotkey, runs the text through a pluggable backend —
an **agent CLI** you already have logged in, or a **translation API** — and shows the result in a
non‑focus‑stealing acrylic popup.

> Status: MVP. Built and verified on this machine (.NET 9, Windows 11). claude + codex translate
> end‑to‑end live; Google Translate + Doubao request/response paths are unit‑verified (fill a key to
> use them). See **Backend status** below.

## What it does

- **Dual trigger** — clipboard watcher (复制即翻译, can be paused) + a global hotkey that translates
  the current clipboard text. The hotkey is configurable and registration conflicts are reported.
- **6 pluggable backends** behind one adapter:
  - CLI: `claude` (Claude Code), `codex` (OpenAI Codex), `copilot` (GitHub Copilot CLI), `agy`
    (Google Antigravity, with a `gemini` fallback).
  - HTTP API: `google-v2` (Google Cloud Translation v2), `doubao` (doubao‑seed‑translation on 火山方舟).
- **Acrylic popup** — floats top‑centre of the primary monitor, never steals focus
  (`WS_EX_NOACTIVATE`), shows source + translation + a copy button, stays while hovered, auto‑dismisses.
- **Tray app** — system‑tray icon with a listen toggle, settings, and exit. State persists across restarts.
- **Settings window** — pick a backend, choose a model (editable, from a catalog), set the hotkey,
  fill API keys, tune the popup. Writes `config.json` and hot‑reloads.

## Requirements

- Windows 11, .NET 9 SDK/runtime (Windows Desktop).
- For CLI backends: the corresponding CLI installed and **logged in** (`claude`, `codex`,
  `copilot`, `agy`/`gemini`).
- For API backends: an API key (filled in Settings, stored only in your local `config.json`).

## Build & run

```powershell
dotnet build TranslateTheDamn.sln -c Release
.\src\TranslateTheDamn.App\bin\Release\net9.0-windows\TranslateTheDamn.exe
```

The app has no main window — look for the tray icon (green = listening, grey = paused). Double‑click
the tray icon or use its menu to open Settings.

## Configuration

First run bootstraps `%USERPROFILE%\.translatethedamn\config.json` with sensible defaults; after that
the Settings UI (and the file) are the source of truth. Secrets (`apiKey`) live only in that file and
are never committed.

The translation rules live in `translation.promptTemplate` (English source ⇒ keep technical terms in
English, translate the rest; non‑English ⇒ translate everything; keep code blocks intact). The LLM
self‑detects the source language. `modelCatalog` is the editable per‑backend model list.

## Backend status

| backend | kind | status |
|---------|------|--------|
| `claude` | CLI | ✅ verified live (translates correctly) |
| `codex` | CLI | ✅ verified live (translates correctly) |
| `google-v2` | HTTP | ✅ request/parse unit‑tested — fill an API key to use |
| `doubao` | HTTP | ⚠️ request/parse unit‑tested; confirm with a real ARK key (official docs were JS‑rendered) |
| `copilot` | CLI | ⚠️ best‑effort — needs a GitHub token; has a known Windows `-p` no‑output bug (#1181) |
| `agy` | CLI | ⚠️ best‑effort — known Windows `-p` no‑stdout bug (#27466); falls back to `gemini` |

Notes:
- Agent CLIs are heavyweight (reasoning, context loading) so a translation can take 10–30s — the
  default CLI timeout is 60s. The **HTTP APIs are the fast path**; use them when you want speed.
- CLI backends are spawned from a neutral empty sandbox directory so they never load the project you
  happen to be in. Complex prompts are fed via stdin to avoid Windows shell‑quoting issues.

## Development

```powershell
# offline unit tests (no network / no processes) — dependency-free harness
dotnet run --project tests\TranslateTheDamn.Tests

# opt-in live end-to-end against a real, logged-in CLI
dotnet run --project tests\TranslateTheDamn.Tests -- --live claude
dotnet run --project tests\TranslateTheDamn.Tests -- --live codex
```

The solution is dependency‑free (no external NuGet): WPF + WinForms (tray) + framework JSON/HTTP +
Win32 P/Invoke only. Layout: `Core` (platform‑agnostic, unit‑tested logic) and `App` (WPF/Win32 UI).

Design spec: `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md`.

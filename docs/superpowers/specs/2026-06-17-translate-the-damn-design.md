# translate-the-damn — Design Spec (v1, 2026-06-17)

A lightweight Windows 11 "copy/​hotkey → translate" tool for heavy LLM users. Watches the
clipboard (toggleable) and/or a global hotkey, runs the text through a configurable backend
(agent CLI **or** translation API), and shows the result in a non‑focus‑stealing acrylic popup.

Status: approved design, MVP build in progress. Derived from PRD v0.4 plus four rounds of
convergence + two web/codebase research passes (agent-cli-research, backend-integration-research).

---

## 1. Goals

- "复制即翻译 / 划词即翻译" with the least possible friction.
- Prompt fully controllable; clear EN-vs-non-EN translation rules.
- Pluggable backends behind one adapter so new CLIs/APIs are cheap to add.
- A global switch (persisted) plus a configurable, conflict-checked global hotkey.
- A nice, non-intrusive popup (acrylic, no focus steal, hover-to-keep, auto-dismiss).

Non-goals (v1): macOS/Linux, OCR/image translation, translation memory, account sync.

## 2. Platform & stack

- Windows 11 only. .NET 9, C#. WPF (popup + settings) + WinForms `NotifyIcon` (tray).
- **Zero external NuGet dependencies** (sandbox blocks nuget.org; also keeps the app lean).
  Framework only: WPF, WinForms, `System.Text.Json`, `System.Net.Http`, Win32 P/Invoke.
- Settings window: WPF with Win11 **Mica** backdrop. Popup: WPF with **Acrylic** backdrop
  (both via DWM `DwmSetWindowAttribute`, no WinUI/WindowsAppSDK dependency).

## 3. Architecture

Single long-running tray process, no main window. Layers:

```
 App (net9.0-windows, WPF+WinForms)
   TrayIcon ─ ClipboardListener ─ HotkeyService ─ PopupWindow ─ SettingsWindow
                         │
                         ▼
   TranslationPipeline (orchestration: filter → translate → present)
                         │
 Core (net9.0, platform-agnostic, unit-tested)
   ITranslator  ◄── TranslatorRegistry
     ├ ProcessTranslator  (claude, codex, copilot, agy[+gemini])
     └ HttpTranslator     (google-v2, doubao,  P1: openai-compatible)
   ConfigService (bootstrap + read/write %USERPROFILE%\.translatethedamn\config.json)
   PathResolver  (PATH/PATHEXT + knownInstallPaths, .cmd/.ps1 wrapping)
   PromptBuilder (EN vs non-EN rules)  ·  Models (request/result/status)
```

All testable logic lives in **Core** so the test harness (net9.0 console) can exercise it
without a Windows-desktop TFM. App is thin UI + Win32 wiring.

### 3.1 Adapter contract (ported from hopper-plugin's `VendorAdapter`)

```csharp
public interface ITranslator {
    string Id { get; }                                   // "claude", "google-v2", ...
    BackendKind Kind { get; }                            // Cli | Http
    Task<TranslationResult> TranslateAsync(TranslationRequest req, CancellationToken ct);
    Task<AuthState> CheckAuthAsync(CancellationToken ct);// soft preflight for the settings "auth" lamp
}

public sealed record TranslationRequest(string Text, string PromptTemplate, BackendConfig Config);
public sealed record TranslationResult(string Text, TranslateStatus Status, string? Error);
public enum TranslateStatus { Success, AuthFail, Timeout, NotFound, BadOutput, UnknownFail }
public enum BackendKind { Cli, Http }
```

`ProcessTranslator` and `HttpTranslator` are the two base classes; concrete backends supply
the per-vendor argv/body building and output parsing.

### 3.2 Reused patterns from hopper-plugin (`F:\workspace\ai\_x_harness\hopper-plugin`)

- **Static registry** (`Dictionary<id, ITranslator>`); add backend = add a class + register.
- **PathResolver**: walk `PATH`×`PATHEXT`; `.cmd/.ps1/.bat` → run via `cmd.exe /c`; fall back
  to `knownInstallPaths` (agy isn't always on PATH → `%LOCALAPPDATA%\agy\bin\agy.exe`).
- **Double timeout**: idle timer (kill on zero output = "stuck") + ceiling timer (hard cap).
- **Kill tree** on timeout: `taskkill /PID <pid> /T /F`.
- **agy log-file diagnosis**: pass `--log-file`, after exit read it to catch
  "exit 0 + empty stdout + auth error in log" (the agy Windows silent-fail case).
- **Status taxonomy** from `parseResult` → drives popup error text + settings auth lamp.

## 4. Triggering (dual-track)

1. **Clipboard watcher** — Win32 `AddClipboardFormatListener` (event-driven). Active only when
   the global switch is ON. Each clipboard update enters the pipeline.
2. **Global hotkey** — `RegisterHotKey`; always active; translates the **current clipboard text**
   (latest item). Configurable; registration failure ⇒ surfaced as a conflict in settings.

### 4.1 Pipeline filters / safety

- **Self-write guard**: when we write to the clipboard (copy-button / optional overwrite mode),
  set a guard flag (+ remember the text hash) so the watcher ignores that change → no loop.
- Skip when: switch off (clipboard path), non-text, empty/whitespace, length over a max bound.
- **Dedupe** consecutive identical clipboard content (clipboard path only; hotkey always runs).
- **Debounce** rapid clipboard bursts.
- **Supersede**: a new trigger cancels an in-flight translation (CancellationToken).
- **Recent-translation cache** (up to **5 entries**, most-recently-used order): before calling the
  model, search **all** cached entries; if the source text matches a cached **successful** result
  **and** the active backend + model are unchanged, return that entry instantly (skip the model) and
  promote it to most-recent. On a miss, call the model and, on success, insert the new result at the
  front; when the cache exceeds 5 entries the **least-recently-used** entry is evicted. A re-query of
  a cached entry counts as a hit **and** refreshes its recency (so it survives later evictions).
  Switching backend or model changes the key ⇒ forced re-translate. Only successful results are
  cached; settings changes clear the whole cache. The popup browses these entries newest→oldest
  (see §8). Main case: repeated hotkey on unchanged clipboard content + quick recall of recent ones.
- Show a "翻译中…" popup immediately, then update in place with the result.

## 5. Translation rules / prompt

Default template (editable in config). The LLM self-detects source language (decision: no local
language detection):

> 源语言为英文时:专业术语/技术名词保留英文,其余描述性内容译为简体中文。
> 源语言为非英文时:全部译为简体中文(含代码注释、变量名解释)。
> 代码块、命令行、配置示例保持原样,仅翻译其中说明性文字。只输出译文,不要任何前后缀。
> 内容:\n{content}

`{content}` is substituted with the source text. For the two dedicated translation APIs
(google-v2, doubao) the prompt template is not used — source/target language is structured.

## 6. Backends (6 in v1)

CLI backends are *agentic coding CLIs*, so each is "tamed" into a clean text→text call:
force a light model, suppress approvals/questions, feed empty stdin where needed, strip ANSI,
constrain output via the prompt. Verified invocations (live-checked versions on this machine):

| id | kind | invocation (headless) | model arg | output | auth |
|----|------|------------------------|-----------|--------|------|
| `claude` | cli | `claude -p "{prompt}" --model {m} --output-format text` + **empty stdin** | `--model` (haiku/sonnet/opus/fable or full id) | text mode = clean; `json`→`.result` | claude.ai OAuth or `ANTHROPIC_API_KEY` |
| `codex` | cli | `{prompt}` piped → `codex exec --skip-git-repo-check --sandbox read-only --color never -m {m} -c model_reasoning_effort="low" -` | `-m` | stdout clean (chrome→stderr); `--json`→`item.text` | ChatGPT login or `CODEX_API_KEY` |
| `copilot` | cli | `copilot -p "{prompt}" -s --no-ask-user --model {m}` | `--model` | `-s` = answer only; no json | `COPILOT_GITHUB_TOKEN` (fine-grained PAT, Copilot Requests) |
| `agy` | cli | `agy -p "{prompt}" --log-file {tmp}` | `--model` (often n/a) | stdout; if empty+exit0 read log; **fallback `gemini -p "{prompt}" --output-format text`** | `ANTIGRAVITY_API_KEY`/OAuth (gemini: `GEMINI_API_KEY`) |
| `google-v2` | http | `POST https://translation.googleapis.com/language/translate/v2` | n/a (NMT) | `data.translations[0].translatedText` | header `x-goog-api-key: {key}` |
| `doubao` | http | `POST https://ark.cn-beijing.volces.com/api/v3/responses` | `model` field | `output[].type==message → content[].type==output_text → .text` | `Authorization: Bearer {ARK_API_KEY}` |

Known Windows risks to verify by smoke test before relying on them: `copilot -p` no-output
(copilot-cli #1181) and `agy -p` no-stdout (gemini-cli #27466). The agy log-file path + gemini
fallback mitigate the latter.

### 6.1 Google Cloud Translation v2 (Basic) — request

```
POST .../language/translate/v2     Header: x-goog-api-key, Content-Type: application/json; charset=utf-8
Body: { "q": "<text>", "target": "zh-CN", "format": "text" }   // omit "source" ⇒ auto-detect; omit model ⇒ NMT
Parse: data.translations[0].translatedText
```
Gotchas: `format` defaults to `html` (escapes) → always send `text`; omit empty `source`/`model`
fields entirely (don't send `""`); v2 only edition that accepts API keys.

### 6.2 doubao-seed-translation (火山方舟 Ark Responses API) — request

```
POST .../api/v3/responses          Header: Authorization: Bearer {ARK_API_KEY}
Body: { "model":"doubao-seed-translation-250915",
        "input":[{"role":"user","content":[
          {"type":"input_text","text":"<text>",
           "translation_options":{"target_language":"zh"}}]}] }   // omit source_language ⇒ auto
Parse: output[] where type=="message" → content[] where type=="output_text" → .text (don't assume output[0])
```
Gotchas: must be `/responses`, **not** `/chat/completions` (400 otherwise); language goes in
`translation_options`, not chat text; ~4K in / 3K out chars (chunk long input); per-character billing.
Confidence medium (official docs JS-rendered) → verify with a real key during the usage phase.

## 7. config.json (single source of truth)

Path: `%USERPROFILE%\.translatethedamn\config.json`. On first run (file absent) the app writes
a **hardcoded default** (below) and thereafter the settings UI only reads/writes this file.
`modelCatalog` is the materialized "built-in model list" (no CLI can list models reliably) and is
**user-editable / free-text** in the model combobox. This bootstrap is intentionally temporary —
later it may be replaced by a remote/dynamic catalog.

```json
{
  "version": 1,
  "general": { "listenClipboard": true, "activeBackend": "claude", "startWithWindows": false },
  "hotkey":  { "translate": "Ctrl+Alt+T", "toggleListen": "" },
  "popup":   { "style": "acrylic", "autoDismissSeconds": 6, "keepOnHover": true, "position": "top-center" },
  "translation": { "targetLanguageDefault": "zh-CN", "maxChars": 8000,
    "promptTemplate": "源语言为英文则术语保留英文、其余译为简体中文;非英文则全部译为简体中文;代码块保持原样;只输出译文。\n\n内容:\n{content}" },
  "backends": {
    "claude":    { "type": "cli",  "command": "claude",  "model": "haiku",           "outputFormat": "text", "timeoutSec": 30 },
    "codex":     { "type": "cli",  "command": "codex",   "model": "gpt-5.4-mini",    "reasoning": "low",      "timeoutSec": 30 },
    "copilot":   { "type": "cli",  "command": "copilot", "model": "claude-haiku-4.5", "timeoutSec": 30 },
    "agy":       { "type": "cli",  "command": "agy",     "model": "gemini-3.5-flash", "fallbackCommand": "gemini", "timeoutSec": 30 },
    "google-v2": { "type": "http", "endpoint": "https://translation.googleapis.com/language/translate/v2", "apiKey": "", "target": "zh-CN", "source": "", "format": "text" },
    "doubao":    { "type": "http", "endpoint": "https://ark.cn-beijing.volces.com/api/v3/responses", "apiKey": "", "model": "doubao-seed-translation-250915", "targetLanguage": "zh", "sourceLanguage": "" }
  },
  "modelCatalog": {
    "claude":  ["haiku", "sonnet", "opus", "fable"],
    "codex":   ["gpt-5.4-mini", "gpt-5.4", "gpt-5.5"],
    "copilot": ["claude-haiku-4.5", "claude-sonnet-4.6", "gpt-5.4", "gemini-3.5-flash"],
    "agy":     ["gemini-3.5-flash", "gemini-3.1-pro"],
    "google-v2": ["nmt"],
    "doubao":  ["doubao-seed-translation-250915"]
  }
}
```

Secrets (`apiKey`) are never committed; they stay only in the user's local config.json.

## 8. Popup UX

WPF window: `WS_EX_NOACTIVATE` + topmost + no taskbar → never steals focus or interrupts typing.
Acrylic backdrop (DWM `DWMSBT_TRANSIENTWINDOW`) + rounded corners; dark scrim so text stays legible.
Shows source text (muted) + translation (prominent) + a **复制译文** button. Floats out top-center
of the **primary** monitor's work area. Mouse hover pauses the dismiss timer; otherwise fades after
`autoDismissSeconds`. States: loading ("翻译中…") → result, or → error (from status taxonomy).

- **Adaptive size** (shared rule): **exactly two fixed window specs** — *normal*, and *large* =
  **2× the normal width × 1.5× the normal height**. The popup uses *large* when the **currently
  displayed entry's source text length is > 500 characters**, otherwise *normal* (pure decision:
  `PopupSizing.sizeClass`). The window snaps to one of the two specs — source is capped at 2 lines
  and the translation **scrolls inside**, so different content lengths never produce an in-between
  size; navigating ◀ ▶ only ever switches between normal and large.
- **History navigation** (shared rule): the popup can browse the recent-translation cache (§4.1) via
  prev/older ◀ and next/newer ▶ controls, showing **one entry at a time** — the just-queried result
  first (= newest), with an "index / total" indicator. Controls disable at the ends; navigating
  re-renders from cache and **never re-invokes the model**. Size is recomputed per displayed entry.
- **Drag to reposition** (shared rule): the popup can be moved by dragging its **card background**
  (anywhere except the action buttons). Dragging a no-focus-steal window must **not** activate it or
  steal focus from the foreground app. While dragging, the auto-dismiss timer pauses and restarts on
  drop. The position is **session-sticky**: once the user moves it, subsequent popups appear at that
  position (clamped to the primary work area) until the app restarts, when it returns to top-center.

## 9. Settings window

WPF, Win11 Mica backdrop, Fluent-style grouped single page. Groups: 监听与触发 (listen toggle,
hotkey capture w/ live conflict check), 翻译后端 (backend combobox → editable model combobox from
`modelCatalog`, auth lamp + "去登录/设密钥", per-backend fields incl. google/doubao apiKey), 浮窗展示
(style acrylic/solid, autoDismiss slider, keep-on-hover), 通用 (start with Windows). Writes config.json;
hot-reloads the running pipeline.

- **Secret entry** (shared rule): the **API Key field is a masked/secure entry** — the key is never
  rendered in plaintext (Windows `PasswordBox`, macOS `SecureField`, etc.). No reveal control in v1.
- **Single instance** (shared rule): the settings window is **single-instance** — re-invoking "open
  settings" (tray menu or tray double-click) surfaces/refocuses the **existing** window (restoring it
  if minimized) instead of opening a second one.

## 10. Non-functional / risks

- Perf target < 5s; agentic CLIs with heavy reasoning may exceed it → default to light models +
  low reasoning; dedicated APIs (google/doubao) are the fast path.
- Privacy: local-first; remote APIs only when the user fills a key. Secrets never leave config.json.
- Reliability: idle+ceiling timeouts, kill-tree, status-based popup errors, agy log diagnosis.

## 11. MVP scope (Phase 0) & order

Build order (each step builds + tests green before next): Core models/config/path/prompt →
backends (claude, codex, google-v2, doubao first; copilot, agy next, same interface) → pipeline →
tray + switch → clipboard + hotkey → popup → settings. All 6 backends targeted; if a CLI proves
Windows-broken at runtime it degrades gracefully (status error) without blocking the others.

Open items requiring the user (usage phase): fill google/doubao API keys; live smoke-test
copilot/agy on this machine; confirm doubao request shape with a real key.

## 12. Versioning (shared across all platforms)

Two **independent** version numbers — do not conflate them:

1. **App version** — `MAJOR.MINOR.PATCH` (SemVer), the product release version shown to users.
   - **MAJOR**: breaking change to behaviour or config that isn't backward-compatible.
   - **MINOR**: a new, backward-compatible feature (e.g. the translation cache, the popup close button).
   - **PATCH**: backward-compatible fixes only.
   - **Cross-platform rule:** the same `MAJOR.MINOR` denotes the **same feature set** on every
     platform (Windows / macOS / Linux). A platform that hasn't shipped a feature yet stays on the
     lower version; per-platform deltas are tracked in the parity matrix, never by diverging the
     meaning of a version. Release notes/CHANGELOG are coordinated per `MAJOR.MINOR`.
   - **Single source per platform, one value coordinated across them:** Windows = the `<Version>`
     family in the App `.csproj` (drives the exe File/Product version + the settings-window caption,
     read at runtime from the assembly); macOS = `CFBundleShortVersionString` (+ `CFBundleVersion`)
     in `Info.plist`; Linux = the package version (`.deb`/AppImage). Each platform surfaces it in its
     about/settings UI and its package metadata.

2. **Config schema version** — the integer `version` field inside `config.json` (currently `1`).
   This versions the **data format only**, is independent of the app version, and bumps **only** when
   the config structure changes incompatibly. All platforms read/write the same schema version so a
   config file is portable between them.

Current app version: **0.2.0** (translation cache + popup close button). Config schema: **1**.

# translate-the-damn · copy-to-translate, the native way

<a href="README.md">简体中文</a> · <b>English</b>

[![conformance](https://github.com/surebeli/translate-the-damn/actions/workflows/conformance.yml/badge.svg)](https://github.com/surebeli/translate-the-damn/actions/workflows/conformance.yml)
[![release](https://github.com/surebeli/translate-the-damn/actions/workflows/release.yml/badge.svg)](https://github.com/surebeli/translate-the-damn/actions/workflows/release.yml)

> **Copy any foreign text → hit one hotkey → read the translation right where you are.** A **native**
> immersive translator for macOS & Windows that doesn't pull you out of what you're reading. It
> **reuses the LLMs you already have** — an API, a subscription, or a local CLI — so it's bring-your-own-key,
> very low cost, free and open-source.

Looking up one word in a dense foreign page shouldn't mean switching to a dictionary or firing up a whole
LLM — the ROI is terrible. translate-the-damn compresses that to **"copy + one hotkey"**: it watches the
clipboard (toggleable) and a configurable global hotkey, runs the text through a **pluggable backend** —
an **agent CLI** you're already logged into, or a **translation / LLM HTTP API** — and shows the result in
a **non-focus-stealing** floating popup.

<table>
<tr><td align="center"><b>macOS</b></td><td align="center"><b>Windows</b></td></tr>
<tr>
<td width="50%"><img alt="macOS — result popup" src="docs/assets/popup-result-macos.png" width="100%"></td>
<td width="50%"><img alt="Windows — result popup" src="docs/assets/popup-result-windows.png" width="100%"></td>
</tr>
</table>

| Platform | Status | Stack |
|---|---|---|
| **Windows 11** | ✅ shipped | C# / .NET 9, WPF + WinForms tray, Win32 P/Invoke |
| **macOS** (Apple Silicon, 14+) | ✅ shipped, feature-aligned with Windows | Swift, SwiftUI + AppKit, Carbon hotkeys |
| **Linux** (Ubuntu 24.04+) | ⬜ planned | see `docs/PORTING-linux.md` |

## Why this tool: four core advantages

- **🧱 Native per platform.** Windows (WPF/.NET 9) and macOS (SwiftUI/AppKit, Apple Silicon) are **two
  native apps** that share no UI or runtime code — each uses its own OS capabilities (non-activating popup,
  global hotkey, tray / menu bar, acrylic glass). Consistency is enforced by **language-neutral conformance
  vectors + a parity matrix + CI**, not by shipping a cross-platform shell. The result feels light and
  responsive, like part of the system.
- **🔌 Reuse the LLM access you already have — not locked to any vendor.** One declarative manifest
  (`spec/backends.json`) drives three backend families:
  - **Agent CLIs** (use a subscription you're already logged into, no extra key): `claude`, `codex`,
    `copilot`, `agy` (Google Antigravity, falls back to `gemini`), `opencode`, `kimi`, `mimo`.
  - **Translation / LLM HTTP APIs** (bring your own key): `google-v2` (Google Translation v2), `doubao`,
    plus a generic **OpenAI- / Anthropic-protocol HTTP** backend with ready-to-fill DeepSeek / MiMo / Kimi presets.
  - **Custom providers:** point the generic HTTP backend at *any* OpenAI-compatible (`/chat/completions`) or
    Anthropic-compatible (`/messages`) endpoint — base URL + key + a protocol toggle — and delete it when done.
- **💸 Very low cost.** Use a subscription you **already pay for**, or a cheap API key; the CLI path
  effectively rides your existing subscription. **Local models are coming** — near-zero cost and fully offline.
- **🔒 Your data stays local.** Config and secrets live only in `~/.translatethedamn/config.json`
  (`%USERPROFILE%\.translatethedamn\config.json` on Windows), **never** committed, never uploaded.

## Highlights

- **Two triggers, zero context switch.** A pausable clipboard watcher (copy-to-translate) plus a
  configurable global hotkey. Defaults: `⇧⌘C` on macOS, `Shift+Alt+C` on Windows; conflicts are detected
  live in Settings.
- **A popup that never steals focus.** The translation appears in a glass card at top-centre (macOS
  non-activating `NSPanel` / Windows `WS_EX_NOACTIVATE`), so your current app keeps focus and keystrokes.
  Source (italic) above translation (bold), with **Copy / Close**; stays open while hovered, auto-dismisses
  on your timer, and you can **drag the card** to reposition it.
- **Adaptive size + history.** Long source auto-enlarges; **◀ ▶** pages your last 5 translations (e.g.
  `2 / 3`) without re-running them.
- **Built-in backend doctor.** One-click **检测** runs a non-interactive auth/connectivity probe and lights
  a status lamp (checking / OK / fail), so you can confirm a backend works before relying on it.
- **Editable model + per-vendor reasoning tiers.** Pick or type a model (with a live `/models` fetch where
  supported), choose a target language, set reasoning-effort tiers for CLIs that expose them.
- **Recent-translation cache.** The last 5 successful results are cached (key = text + backend + model), so
  repeating an identical translation returns instantly.
- **Light + dark, localized UI.** Settings and popup follow the system appearance; the UI ships in Simplified Chinese.

## Latency by access method (objective data)

Different backends are different **trade-offs**, not "better/worse". So you know what to expect — and to
preempt any "is this method slow?" worry — here is measured single-call latency on an Apple Silicon Mac,
same ~18-word English input, **cold pipeline (no cache)**:

| Access method | Example backends | Measured / call | Notes |
|---|---|---|---|
| **HTTP API** (BYOK) | Kimi / MiMo / DeepSeek presets | **~1–5 s** | one direct HTTP request — the **fast path**; Kimi endpoint as low as ~1s |
| **Custom HTTP** | any OpenAI/Anthropic-compatible endpoint | **~1–6 s** | depends on the service you point at |
| **Agent CLI** (light) | `codex` · `kimi` · `opencode` · `mimo` | **~5–8 s** | each call **cold-starts an agent process** |
| **Agent CLI** (heavy) | `claude` · `copilot` | **~10–16 s** | heavy agents (more reasoning/context) in exchange for "reuse your subscription, zero extra key" |

In short: **want speed → use an HTTP API** (1–5s); **want to ride an existing subscription → use a CLI** —
it's a few seconds slower because it spins up a full agent process each time, a deliberate cost-vs-speed
trade-off, not a bug. A cache hit on a repeated translation is **instant**.

> These backends reflect the **author's own resources and habits**. Want another one (e.g. **Microsoft
> Translator, Alibaba Bailian / Qwen**)? **Open an [issue](https://github.com/surebeli/translate-the-damn/issues)**
> — backends are driven by a declarative manifest, so adding one is easy.

## Install & run

### Download a prebuilt release

Grab the latest archives from the [**Releases**](https://github.com/surebeli/translate-the-damn/releases/latest) page:

- **macOS** (Apple Silicon) — `TranslateTheDamn-<version>-macos-arm64.zip`
- **Windows 11** (x64) — `TranslateTheDamn-<version>-windows-x64.zip`

> **⚠️ macOS Gatekeeper** — the macOS build is **unsigned / un-notarized**, so first launch is blocked.
> Either **right-click the app → Open** (confirm once), or clear the quarantine flag on where you unzipped it:
> ```bash
> xattr -dr com.apple.quarantine /path/to/TranslateTheDamn.app
> ```
> (Not necessarily `/Applications` — use wherever you unzipped.)

### Build from source

**macOS** (Apple Silicon, Xcode 16 / Swift 6 CLI tools):

```bash
./platforms/macos/scripts/build-app.sh        # → platforms/macos/TranslateTheDamn.app
open platforms/macos/TranslateTheDamn.app
```

**Windows 11** (.NET 9 Desktop SDK/runtime):

```powershell
dotnet build platforms\windows\TranslateTheDamn.sln -c Release
.\platforms\windows\src\TranslateTheDamn.App\bin\Release\net9.0-windows\TranslateTheDamn.exe
```

There is **no main window** — look in the menu bar (macOS) / system tray (Windows) for the icon (green =
listening, grey = paused); click it for Settings or quit. On macOS the app intentionally does **not** run in
the App Sandbox (it must spawn your CLIs); for a signed + notarized build use `platforms/macos/scripts/sign-notarize.sh`.

## Usage

On first launch the app writes `~/.translatethedamn/config.json` with sensible defaults. After that, the
Settings window and that file are the source of truth — everything hot-reloads, no restart needed.

<table>
<tr><td align="center"><b>macOS</b></td><td align="center"><b>Windows</b></td></tr>
<tr>
<td width="50%"><img alt="macOS — settings, built-in CLI backend" src="docs/assets/settings-builtin-macos.png" width="100%"></td>
<td width="50%"><img alt="Windows — settings, built-in CLI backend" src="docs/assets/settings-builtin-windows.png" width="100%"></td>
</tr>
</table>

- **Listen & trigger** — toggle the clipboard watcher and set the **translate hotkey**; a live check confirms it's free (✓) or taken.
- **Translation backend** — pick a target language + a backend (e.g. `claude · CLI`), then choose/type a model. Default: `claude` / `haiku`.
- **Popup** — visual style (acrylic / solid), auto-dismiss time, keep-open-while-hovering.
- **General** — launch at login; a footer reminds you config + keys stay on your machine.

**Translate:** copy text (with the watcher on, copy = translate) or press the hotkey. A spinner shows while
the backend runs, then the glass card slides in without stealing focus — **Copy** the result, **Close** to
dismiss, hover to keep it open. Page your last 5 with **◀ ▶**; long source auto-enlarges.

<table>
<tr><td align="center" colspan="2"><b>Translating</b></td><td align="center" colspan="2"><b>History ◀ ▶</b></td></tr>
<tr><td align="center">macOS</td><td align="center">Windows</td><td align="center">macOS</td><td align="center">Windows</td></tr>
<tr>
<td width="25%"><img alt="macOS — translating" src="docs/assets/popup-loading-macos.png" width="100%"></td>
<td width="25%"><img alt="Windows — translating" src="docs/assets/popup-loading-windows.png" width="100%"></td>
<td width="25%"><img alt="macOS — history" src="docs/assets/popup-history-macos.png" width="100%"></td>
<td width="25%"><img alt="Windows — history" src="docs/assets/popup-history-windows.png" width="100%"></td>
</tr>
</table>

If a backend isn't logged in or the network is down, the popup shows a clear **error in red** and points you
back to the doctor in Settings:

<table>
<tr><td align="center"><b>macOS</b></td><td align="center"><b>Windows</b></td></tr>
<tr>
<td width="50%"><img alt="macOS — error state" src="docs/assets/popup-error-macos.png" width="100%"></td>
<td width="50%"><img alt="Windows — error state" src="docs/assets/popup-error-windows.png" width="100%"></td>
</tr>
</table>

**Check a backend** with the **检测** doctor — a non-interactive auth/connectivity probe with a status lamp (OK / fail):

<table>
<tr><td align="center"><b>macOS</b></td><td align="center"><b>Windows</b></td></tr>
<tr>
<td width="50%"><img alt="macOS — doctor lamp OK" src="docs/assets/settings-lamp-ok-macos.png" width="100%"></td>
<td width="50%"><img alt="Windows — doctor lamp OK" src="docs/assets/settings-lamp-ok-windows.png" width="100%"></td>
</tr>
</table>

**HTTP APIs / custom providers:** select an HTTP backend (`doubao`, `google-v2`, or a DeepSeek/MiMo/Kimi
preset) and fill the masked API Key + endpoint; **检测已有密钥** can auto-discover keys already on your
machine (consent-gated, static keys only). For any other service, **新增 provider…** with a base URL + key
and pick **OpenAI (`/chat/completions`)** or **Anthropic (`/messages`)**:

<table>
<tr><td align="center"><b>macOS</b></td><td align="center"><b>Windows</b></td></tr>
<tr>
<td width="50%"><img alt="macOS — custom provider" src="docs/assets/settings-custom-macos.png" width="100%"></td>
<td width="50%"><img alt="Windows — custom provider" src="docs/assets/settings-custom-windows.png" width="100%"></td>
</tr>
</table>

## Configuration

Translation rules are built in (`translation.promptTemplate`): English source ⇒ keep technical terms in
English, translate the rest; non-English source ⇒ translate everything; code/commands stay intact. The target
language is unified via a `{target}` placeholder and selectable in Settings; the LLM self-detects the source.

## Backend notes

- **Agent CLIs** must be installed and **logged in**; they're heavyweight, so a translation takes ~5–16s — the
  **HTTP APIs are the fast path**. CLIs spawn from a neutral sandbox (never load your current project); prompts go via stdin.
- **`claude` / `codex`** are verified live end-to-end on Windows; **`google-v2` / `doubao`** and the HTTP LLM
  providers are request/parse unit-tested — fill a key to use them; **`copilot` / `agy`** are best-effort. Shared
  request/parse, cache, hotkey, config, effort-tier and doctor logic is pinned by the conformance vectors and runs
  green on both Windows and macOS in CI (the vectors are offline — live CLI/HTTP calls aren't exercised in CI).

## Cross-platform

Governed by **[CONSTITUTION.md](./CONSTITUTION.md)** — the single entry point. The laws: change shared behaviour
in `/spec` + `/conformance` **first**; the language-neutral vectors in `conformance/` are the only source of truth
for shared logic; the same `MAJOR.MINOR` means the same feature set on every platform, tracked in
**[PARITY.md](./PARITY.md)**. Vectors run in **CI on every push/PR** via each platform's native runner over the
*same* JSON (Windows `dotnet run`, macOS `swift test`). The pipeline also guards parity drift (coupling gate,
`parity-verify`, `parity-evidence`). Backends are declared once in `spec/backends.json`; macOS reads that manifest
via a generic interpreter (Constitution Law 6), Windows adapters are mid-refactor to match. See
**[docs/CROSS-PLATFORM-PARITY.md](./docs/CROSS-PLATFORM-PARITY.md)**.

## Development

```powershell
dotnet run --project platforms\windows\tests\TranslateTheDamn.Tests   # Windows offline conformance + unit suite
```

```bash
( cd platforms/macos && swift test )          # macOS conformance + unit suite
python3 scripts/parity-drift.py               # cross-platform drift report (stdlib only)
```

The Windows solution is dependency-free (framework-only); the macOS package is Foundation/AppKit only. Both split
`Core` (platform-agnostic, vector-tested logic) from `App` (native UI). Contributions follow a spec-first flow — see
**[CONTRIBUTING.md](./CONTRIBUTING.md)**.

## License

[MIT](./LICENSE) © translate-the-damn contributors

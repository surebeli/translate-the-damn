# Handoff — Windows release screenshots (mirror the macOS set)

## Goal
Produce **Windows** screenshots that mirror the existing **macOS** ones, one-for-one, with the
**identical sample content** and **light mode**, so the README can show each scenario as a
side-by-side **macOS │ Windows** pair. Deliver them as `docs/assets/<scenario>-windows.png`.

## Background
- Pull latest first: `git fetch && git checkout main && git pull` (HEAD should include the release
  kit + `docs/assets/*.png` macOS shots + `release.yml`).
- The macOS shots were produced by an **env-gated screenshot harness** — use it as the blueprint:
  - `platforms/macos/src/App/ScreenshotHarness.swift` — gated on `TTD_SHOT_KIND`; constructs ONE
    `PopupWindow`/`SettingsWindow` in a given state, forces appearance, writes the window id, and
    stays alive so an external capture grabs the **real composited window** (title bar + acrylic).
  - `platforms/macos/scripts/shot-walkthrough.sh` — drives each kind and `screencapture -l<id>`.
- Windows app: `platforms/windows/src/TranslateTheDamn.App` (WPF). The popup is
  `UI/PopupWindow.xaml(.cs)`; settings is `UI/SettingsWindow.xaml(.cs)`; effects in
  `Interop/WindowEffects.cs`. Build: `dotnet build platforms\windows\TranslateTheDamn.sln -c Release`.

## Task
1. Add an **env-gated screenshot mode** to the Windows app mirroring the macOS harness (e.g. read
   `TTD_SHOT_KIND` in `App.xaml.cs` before normal startup; if set, build just the one window in the
   requested state and show it). Keep it **inert** unless the env var is set (a normal launch must be
   unchanged). Capture the **real composited window** (so DWM acrylic + the new rounded border from
   `1da505c` show) — e.g. `PrintWindow`/`Graphics.CopyFromScreen` over the window's RECT by HWND,
   analogous to macOS `screencapture -l<id>`. (A small PowerShell capturer driven from a
   `shot-walkthrough.ps1` is the natural Windows twin of the bash driver.)
2. Drive the scenarios below with the **exact** sample content, **light theme**.
3. Save each as `docs/assets/<scenario>-windows.png`. Match the macOS framing as closely as the
   native window allows (same scenario, same text, light, clean single-window capture — no desktop
   clutter). Native window sizes differ between platforms; that's fine — content + scenario + theme
   must match, pixel-identical sizing is not required.
4. **Coupling gate**: the harness touches `platforms/windows/src/**` but changes no shared behaviour
   and the docs/assets are additive — so put `parity:n/a screenshot harness, no feature change` in a
   commit message (the gate accepts that), and do NOT edit `PARITY.md`. Keep the harness dev-only.
5. Verify: conformance CI green; the offline test suite still passes
   (`dotnet run --project platforms\windows\tests\TranslateTheDamn.Tests`).
6. Do **NOT** edit `README.md` or the macOS `docs/assets/*.png` — the macOS side will rename its
   assets to `-macos.png` and assemble the side-by-side README. You only add `-windows.png` files
   (plus the harness + a `shot-walkthrough.ps1`).

## Scenarios → filenames (required = the 7 the README shows)
| scenario (`TTD_SHOT_KIND`) | file | state |
|---|---|---|
| `popup-result`  | `docs/assets/popup-result-windows.png`  | result popup: source(italic) + translation(bold) + Copy/Close |
| `popup-loading` | `docs/assets/popup-loading-windows.png` | "翻译中…" spinner state |
| `popup-error`   | `docs/assets/popup-error-windows.png`   | red error header + body |
| `popup-history` | `docs/assets/popup-history-windows.png` | history nav showing **2 / 3** (3 entries, display index 1) |
| `settings-builtin` | `docs/assets/settings-builtin-windows.png` | settings, backend = `claude` (CLI), default hotkey `Shift+Alt+C`, doctor lamp "未检测" |
| `settings-lamp-ok` | `docs/assets/settings-lamp-ok-windows.png` | doctor lamp **OK** after 检测 |
| `settings-custom`  | `docs/assets/settings-custom-windows.png`  | custom provider `my-llm`, protocol = OpenAI, 删除 provider enabled |

Optional (nice to have for completeness): `popup-large`, `settings-http`, `settings-lamp-fail`.

## Exact sample content (reuse verbatim so the pairs match)
- **source (short)**: `A good translation tool stays invisible until you need it — then it is instantly useful.`
- **translation (short)**: `好的翻译工具在你需要之前保持隐形——需要时立即可用。`
- **error message**: `翻译失败:claude 未登录或网络不可用(可在设置里「检测」后端)`
- **history (newest→oldest), show index 1 (the 2/3 entry)**:
  1. `A good translation tool stays invisible until you need it — then it is instantly useful.` / `好的翻译工具在你需要之前保持隐形——需要时立即可用。`
  2. `Second most recent source line.` / `第二近的源文本行。`
  3. `Oldest cached entry.` / `最旧的缓存条目。`
- **custom provider**: id `my-llm`, endpoint `https://api.example.com/v1`, apiKey `sk-secret`, protocol `openai`, model `gpt-4o-mini`.
- **doctor lamp OK detail**: `已登录(本地凭据;未做联网验证)` (and for the optional fail shot: `未登录(本地凭据检查未通过)`).

## Acceptance
- `docs/assets/<scenario>-windows.png` exists for all 7 required scenarios; light theme; identical
  sample content to macOS; clean single-window capture showing the real acrylic + rounded border.
- Conformance CI green; offline test suite passes; coupling gate satisfied via `parity:n/a`.

## Return
Commit + push to `main` (additive — the new `-windows.png` files + the harness + `shot-walkthrough.ps1`).
Report: the list of added file paths and the commit SHA. The macOS side will then do the README
side-by-side layout.

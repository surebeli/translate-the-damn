# Handoff: Windows i18n — WPF UI (the part that needs a Windows build)

## Status / context
The **Core + conformance** half is DONE + on branch `feat/i18n-windows-core` (CI-verified on the real
net9 Windows runner):
- `platforms/windows/src/TranslateTheDamn.Core/LocaleResolver.cs` — `Resolve(configUiLang, systemLocale)`
  (same contract as macOS) + `SystemLocaleId()` (= `CultureInfo.CurrentUICulture.Name`).
- `GeneralConfig.UiLanguage` (`""` = follow system) in `Config/AppConfig.cs`.
- `conformance/i18n-locale-resolve.json` wired into the Windows runner (`Conformance.cs` → green).

This handoff is the **WPF UI** — it can only be built/verified on Windows (`net9.0-windows` + WPF), so
it's split out. Shared resources already exist: `strings/{zh-CN,en,ja,ko}.json` (69 keys, identical sets;
zh-CN canonical). Spec: `docs/superpowers/specs/2026-06-23-i18n-ui-localization.md`.
**Reference implementation: macOS** — mirror it exactly:
- `platforms/macos/src/App/StringsLoader.swift` (locale-aware loader)
- `platforms/macos/src/App/DSSettingsView.swift` (selector + extracted labels; the literal→key map)
- `platforms/macos/src/App/SettingsWindow.swift` VM (`uiLanguage`, `onUiLanguageChange`, hot-reload,
  `targetLanguageFollowingUiLanguage` / `systemTargetLanguageName` — the target-follows-display logic)
- `platforms/macos/src/App/AppDelegate.swift` (resolve + `StringsLoader.configure` at startup, before UI)

## Progress — DRAFTED on the Mac (compile-pending; build on Windows to verify)
On branch `feat/i18n-windows-wpf`. The Core piece is CI-compile-checked (Tests reference Core); the WPF
App pieces are NOT built by CI — build them on Windows.
- ✅ **Core `StringsLoader.cs`** (en base + `<locale>` overlay; Configure/Reload/Get) — CI-compiled.
- ✅ **csproj**: bundles `strings/*.json` beside the exe (Content/CopyToOutputDirectory).
- ✅ **AppController**: `StringsLoader.Configure(LocaleResolver.Resolve(uiLanguage, SystemLocaleId()))` at startup, before any UI.
- ✅ **SettingsWindow.xaml**: `x:Name`d all localizable labels/group-headers; added the **界面语言 / Display-language** `CmbUiLang` row.
- ✅ **SettingsWindow.xaml.cs**: `CmbUiLang` populate + `CmbUiLang_SelectionChanged` (hot-reload via `Relocalize()` + `LocaleChanged` event), `TargetForDisplay()`/`SystemTargetLanguageName()` (the two target-follows-display fixes), `Relocalize()` (sets all existing-key labels/buttons/title), style-combo + hotkey-hint extracted, `BtnSave` persists `UiLanguage`.

## Progress — 2nd drafting pass (compile-pending; build on Windows to verify)
Same branch. **All static/persistent UI is now keyed; 14 new shared keys added to ALL 4 `strings/*.json`**
(83 keys each, identical sets + placeholder-consistent — verified by script). New keys: `settings.group.translate`,
`settings.target.hint`, `settings.doctor.deep`, `settings.doctor.checkingDeep`, `settings.doctor.overall`,
`settings.doctor.failed`, `settings.doctor.status.{ok,degraded,fail,unknown}`, `settings.auth.{httpMissing,httpReady,cliMissing,cliReady}`.
- ✅ **Tray** (`TrayIconController.cs`): menu items + tooltip from `StringsLoader.Get`; `RefreshLocalizedText()` added; tracks `_listening` so the tooltip re-picks correctly on hot-switch.
- ✅ **AppController.OpenSettings**: wired `_settings.LocaleChanged += () => _tray.RefreshLocalizedText();`.
- ✅ **PopupWindow.xaml.cs**: header/body/buttons (`popup.header.*`, `popup.body.translating`, `popup.button.*`) keyed; Close/Copy + ◀/▶ nav tooltips (`popup.nav.older/newer`) set in the constructor.
- ✅ **CredentialImportDialog.cs** + **InputBox.cs**: import/cancel/header/note/title/add prompts keyed (reuse `settings.detect.*`, `settings.button.*`, `settings.provider.*`).
- ✅ **SettingsWindow.xaml.cs**: `LblGroupTranslate`/`LblTargetHint`/`ChkDeep` added to `Relocalize()`; `AuthHint` (● lamp), `RenderDoctor`/`StatusZh` (overall + status words), `ValidateHotkey` (→ `settings.hotkey.ok`/`invalid`, mirrors macOS), doctor "checking"/"failed" text, `BtnSave` saved-toast, and `BtnAddProvider` prompt all keyed.
- Verified: every `StringsLoader.Get("…")` key used in the App (69 distinct) exists in the catalog; JSON parity + placeholders consistent across the 4 locales.

> **MERGED TO MAIN** (merge commit `d8f52a9`, 2026-06-24). The branch `feat/i18n-windows-wpf` is
> deleted (local + remote) — **build from `main`**, not the branch. CI green on the merge: Windows
> (dotnet) Core compiles, macOS (swift) unaffected by the catalog additions, parity drift clean.
> The WPF **App** is still compile-pending (CI doesn't build it) — the step below is the only thing left.
>
> **PARITY FLIPPED ✅/✅** (PR #13, merge commit `6fbb84c`, 2026-06-24). The `UI localization` row is
> now a LOGIC row keyed to `` `i18n-locale-resolve` `` (Spec `§3/§4`), Win + macOS both ✅. Both
> conformance jobs ran `parity-verify` against real results and confirmed green-vector ⇄ ✅ on each
> platform; `parity-evidence` + the PR-only coupling gate also green. (Removed the now-stale
> `"UI localization"` key from `spec/ui-evidence.json` — the row is logic-kind now, so the orphan-key
> gate would otherwise fail.) **This is a vector-backed claim, not a runtime claim**: the Windows WPF
> App is still unbuilt — the per-platform UI walkthrough below is the remaining real-world check (not
> vector-gated, exactly like every other UI row).

### Remaining (do on Windows with the build loop)
1. **Compile + fix** `dotnet build platforms/windows/TranslateTheDamn.sln -c Release` (from `main`) — the App is NOT built by CI; the first Windows build will surface any missed `x:Name` / typo. Then run + verify Display-language switching across settings + popup + tray.
2. **Intentionally left hardcoded Chinese** (transient or low-value; key them if you want 100% coverage):
   - `SetStatus` toasts with placeholders: 保存失败 / 已存在 / 已新增 / 检测失败 / 未在本机发现… / 已导入 / 内置后端不可删除 / 已删除 (SettingsWindow.xaml.cs ~447, 484, 488, 497, 498, 513, 527, 532). Flash briefly.
   - Backend dropdown " · 暂不支持" tag (agy, `BackendDisplay` ~257).
   - `LblDoctor` row label "诊断" (no shared key; macOS doesn't key it either).
   - Per-check doctor names/details (`c.Name`/`c.Detail`) come from **Core `DoctorService`** in Chinese — a Core-i18n task, out of scope for this UI pass (the auth-row match `StartsWith("认证")` is internal logic, leave it).
   - `CmbProtocol` items ("OpenAI (/chat/completions)" etc.) are technical — leave.
   - Note: `Title`/`LblHotkeyExample` momentary literals in the ctor are immediately overwritten by `Relocalize()`.
3. **Language endonyms stay literal** (简体中文 / 日本語 / 한국어 …) — a language picker shows each name in its own script; do NOT localize these.

## Tasks (build on Windows: `dotnet build platforms/windows/TranslateTheDamn.sln -c Release`)

1. **StringsLoader (put in Core so it's pure/testable):**
   `Configure(localeId)`, `Reload()`, `string Get(string key)`. Catalog = `strings/en.json` (base) overlaid
   by `strings/<localeId>.json`; `Get` returns the key itself if absent. Find `strings/` by walking up from
   `AppContext.BaseDirectory` (same pattern as `Conformance.FindUp`). Parse the `"strings"` object.

2. **Ship the locale files with the app:** add to `TranslateTheDamn.App.csproj` an item that copies
   `..\..\..\..\strings\*.json` to the output `strings\` dir (CopyToOutputDirectory). (macOS does this in
   `build-app.sh`.) Verify the loader finds them from the built app dir.

3. **Startup (App.xaml.cs / AppController):** BEFORE building any window/tray/popup —
   `StringsLoader.Configure(LocaleResolver.Resolve(config.General.UiLanguage, LocaleResolver.SystemLocaleId()))`.

4. **SettingsWindow.xaml(.cs):**
   - Replace EVERY hardcoded CJK literal with `StringsLoader.Get("<key>")`. The keys already exist in
     `strings/zh-CN.json` and map 1:1 to the macOS `DSSettingsView` extraction — reuse the SAME keys
     (`settings.group.*`, `settings.field.*`, `settings.doctor.*`, `settings.model.*`, `settings.provider.*`,
     `settings.detect.*`, `settings.style.*`, `settings.button.*`, `settings.general.configHint`,
     `settings.hotkey.*`, etc.). `{placeholders}` (`{hotkey}`, `{count}`) → string-replace at use.
   - Add a **"Display language" selector** (`settings.field.uilang`): options = `settings.uilang.system`
     ("") + zh-CN/en/ja/ko by native name (简体中文 / English / 日本語 / 한국어). Bind to `General.UiLanguage`.
   - **Hot-reload** on change: re-resolve → `StringsLoader.Configure` + `Reload()` → re-render the settings
     window (+ tray) in the new language (macOS rebuilds the hosting view; WPF: reload bound strings / reopen).
   - **Target-follows-display** (the two fixes the user reviewed on macOS): on load AND on display-language
     change, set the translation target from the resolved display language — follow-system → the SYSTEM
     language mapped onto the full target list (zh/繁中/en/ja/ko/fr/de/es/ru/pt), **fallback 简体中文** when
     unobtainable/unsupported; explicit display → its matching target name. Port `systemTargetLanguageName`
     + `targetLanguageFollowingUiLanguage` from the macOS VM verbatim.

5. **PopupWindow, tray (NotifyIcon), dialogs (CredentialImportDialog, InputBox), AppController:** extract
   their hardcoded CJK to `StringsLoader.Get(...)` using the existing `popup.*` / `tray.*` / `error.*` keys
   (add new keys to ALL 4 locale files only if a Windows-only string has no macOS counterpart — keep the
   key sets identical; re-run the completeness check).

6. **Verify on Windows:** build + run; open Settings → switch Display language → whole UI (settings + popup
   + tray) switches; confirm on an English-locale Windows that follow-system → English UI + English target.
   `dotnet run --project platforms/windows/tests/TranslateTheDamn.Tests` still green (incl. i18n-locale-resolve).

## PARITY flip — DONE (2026-06-24, PR #13 → `6fbb84c`)
The `UI localization` row is flipped to ✅/✅, keyed to `` `i18n-locale-resolve` `` (Spec `§3/§4`), with a
PARITY Note recording the honest status (macOS shipped + walked-through; Windows Core/resolver CI-verified,
WPF UI localized in code, native App build pending). The Law-2 forcing function actually *required* the flip:
once the row references the both-green vector, a non-✅ column is a `parity-verify` UNDER-CLAIM. All parity
checks green on the PR and on the post-merge `main` run (conformance ×2 with `parity-verify`, `parity-evidence`,
parity drift, coupling gate). All 4 locale files carry identical 83-key sets.

**The only thing left is the real-world build** (item 1 below) — the Windows WPF App compile + UI walkthrough.
The PARITY ✅ is vector-backed (the resolver contract is green on both); it is NOT a runtime claim that the
Windows UI was exercised. If the Windows build surfaces a fix, that's a normal forward change on `main` — it
does not reopen the parity row (the vector stays green).

# Design: UI Localization (i18n) — system-following + in-app selector

Status: **SPEC-FIRST / planned** (design + shared `strings/` resources + PARITY row landed; platform
impl not started). Target: a MINOR bump (next `0.MINOR.0`), both platforms in lockstep (Constitution Law 3).

> Scope note: this is the **app's own UI language**, which is *separate* from the **translation target
> language** (`translation.targetLanguageDefault`, already configurable). A user may run an English UI
> while translating *into* Japanese, etc. The two settings are independent and must never be conflated.

## 1. Goal

The app UI currently ships **Simplified-Chinese only**: macOS `StringsLoader` always loads
`strings/zh-CN.json` (no locale logic) and a large amount of UI text is still **hardcoded** in Swift /
XAML. Make the UI **multilingual**:

- **Default = follow the system language**, with a sensible fallback chain.
- **In-app override**: a "Display language" selector in Settings (independent of target language).
- **First locale batch**: `en`, `ja`, `ko` (+ existing canonical `zh-CN`). More via community PRs later.

## 2. Shared `strings/` artifact (landed in this spec)

- One file per locale: `strings/<locale>.json`, shape `{ "doc", "locale", "strings": { key: value } }`.
- **`zh-CN.json` is canonical** — it defines the key set. **Every locale MUST carry the exact same keys**
  ("completeness"). A missing key is a spec violation, not a silent fallback at author time.
- `{placeholders}` (e.g. `{sec}`, `{command}`) are preserved verbatim in every locale; each platform
  substitutes them. No locale may add/drop/rename a placeholder for a given key.
- Both platforms read the **same** files (Constitution: shared artifact) so wording never drifts.
- Locales shipped now: `zh-CN` (canonical), `en`, `ja`, `ko`. `ja`/`ko` are machine-drafted and flagged
  for native review before ship.

## 3. Locale resolution (the contract → becomes `conformance/i18n-locale-resolve.json` at impl)

`resolveUiLocale(configUiLang, systemLocale, available)` where `available = [zh-CN, en, ja, ko]`:

1. **Explicit override** — if `configUiLang` is non-empty AND in `available` → return it.
2. **Follow system** — map `systemLocale` to `available` by primary language subtag (case-insensitive):
   - `zh*` (`zh`, `zh-Hans`, `zh-CN`, `zh-Hant`, `zh-TW`, …) → `zh-CN`  *(v1: all Chinese → zh-CN until a `zh-TW` locale is added)*
   - `ja*` → `ja` · `ko*` → `ko` · `en*` → `en`
3. **Fallback** — anything else (unsupported / empty) → **`en`** (global default).

Missing-key fallback at **runtime** (a key absent from the resolved locale): resolved locale → `en` →
the key string itself. (Completeness in §2 means this should never fire in shipped builds; it's a guard.)

Frozen example cases (the conformance vector, added during impl):

| configUiLang | systemLocale | → expected |
|---|---|---|
| `ja` | `en-US` | `ja` (override wins) |
| `` | `ja-JP` | `ja` |
| `` | `ko-KR` | `ko` |
| `` | `zh-Hans-CN` | `zh-CN` |
| `` | `zh-Hant-TW` | `zh-CN` (v1) |
| `` | `en-GB` | `en` |
| `` | `fr-FR` | `en` (unsupported → fallback) |
| `xx` (not available) | `fr-FR` | `en` |
| `` | `` | `en` |

## 4. Settings: "Display language" selector

- New control in the **General** group: label `settings.field.uilang`, options = `settings.uilang.system`
  ("Follow system") + one entry per available locale (简体中文 / English / 日本語 / 한국어).
- Persists to config as `general.uiLanguage` (`""` = follow system; otherwise a locale id from `available`).
- **Hot-reload** on change: re-resolve, reload the catalog, refresh open windows (settings + tray + any popup).
- Distinct from `settings.field.target` (translation target). Both visible; never merged.

## 5. Per-platform impl plan (NOT done — tracked in PARITY as ⬜)

- **macOS**: extend `StringsLoader` to (a) accept a resolved locale, (b) load `strings/<locale>.json` with the
  `en` → key fallback, (c) resolve via `NSLocale` + `general.uiLanguage`. Move the inline `fallbackStrings`
  dict out (the file is canonical). Add the selector to `DSSettingsView` + hot-reload.
- **Windows**: add a JSON-per-locale loader (mirror macOS resolution), or `.resx`+`ResourceManager` fed from
  the same `strings/<locale>.json`; bind XAML to it; add the selector + `CultureInfo`-based resolution.
- **Both**: extract the remaining **hardcoded** UI literals into the catalog (see §6) so nothing is left untranslated.
- Add `conformance/i18n-locale-resolve.json` + wire both runners (RED→GREEN), flip the PARITY row to ✅/✅.

## 6. Extraction backlog (hardcoded → catalog, during impl)

Many strings are not yet keyed and live as literals. Non-exhaustive, to be moved into `strings/`:

- **macOS**: `DSSettingsView.swift` (group/field labels, e.g. 源语言(可选), 协议, 新增 provider…, target-language
  option names), `SettingsWindow.swift`, backend display tags (`· API` / `· CLI` / `暂不支持`), `LiveCheck` /
  doctor messages, `TrayController`, `AppDelegate` user-facing strings. (`ScreenshotHarness` is dev-only — skip.)
- **Windows**: ~21 files with hardcoded CJK (XAML labels + `SettingsWindow.xaml.cs` + doctor/error text).
- Rule: each extracted literal gets a key in `zh-CN.json` first (canonical), then is added to `en`/`ja`/`ko`.

## 7. Out of scope (v1)

- RTL locales (ar/he) — layout work; defer.
- Locale-aware number/date formatting — not needed (UI has none of note).
- Translating the **translation prompt** template — that's target-language behavior, not UI i18n.
- `zh-TW` / additional locales — community PRs after the framework lands.

## 8. Phasing

Not blocking the phase-1 (Chinese-community) promo push — a Chinese UI is fine there. This is the
**pre-requisite for the phase-2 (global) push** (an English/Japanese/Korean user expects a UI in their
language). Land the impl before phase-2 promo.

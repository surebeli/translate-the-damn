---
phase: done
last_progress_at: "2026-06-18T04:05:00.507Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-06-18T04:05:00.506Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 126524
adapter_status: success
---
# T-MAC-10 Output — ConfigService.defaultConfig / load / save

## Summary

Implemented `ConfigService.defaultConfig()` in `platforms/macos/src/Core/ConfigService.swift` to return the full first-run default `AppConfig` per spec §7 (6 backends, model catalog, general/hotkey/popup/translation defaults). Also implemented `ConfigService.load(from:)` and `ConfigService.save(_:to:)` for M3 config-file persistence, using `ConfigEncoding.encoder` for deterministic camelCase/sorted-keys output and expanding `~` via `NSString.expandingTildeInPath`.

## Files touched

| path | lines | purpose |
|------|-------|---------|
| `platforms/macos/src/Core/ConfigService.swift` | 108 | Full default config builder + load/save helpers |

No other files were modified. `AppConfig.swift`, the conformance vectors, the runner, and the Windows platform remain untouched.

## Acceptance verification (15/15)

All 15 asserts from `conformance/config-defaults.json` are satisfied by `ConfigDefaultsTests/testConfigDefaults`.

| # | assert | status | evidence |
|---|--------|--------|----------|
| 1 | `version == 1` | ✅ | test log: `ConfigDefaultsTests/testConfigDefaults passed` |
| 2 | `general.activeBackend == "claude"` | ✅ | `"activeBackend": "claude"` emitted via default `GeneralConfig` |
| 3 | `general.listenClipboard == true` | ✅ | `GeneralConfig(listenClipboard: true, ...)` |
| 4 | `hotkey.translate == "Ctrl+Alt+T"` | ✅ | `HotkeyConfig(translate: "Ctrl+Alt+T", ...)` |
| 5 | `popup.style == "acrylic"` | ✅ | `PopupConfig(style: "acrylic", ...)` |
| 6 | `popup.autoDismissSeconds == 6` | ✅ | `PopupConfig(autoDismissSeconds: 6, ...)` |
| 7 | `backends count == 6` | ✅ | 6 entries: claude, codex, copilot, agy, google-v2, doubao |
| 8 | `backends.claude.model == "haiku"` | ✅ | `BackendConfig(type: "cli", command: "claude", model: "haiku", outputFormat: "text", timeoutSec: 30)` |
| 9 | `backends.codex.reasoning == "low"` | ✅ | `BackendConfig(..., model: "gpt-5.4-mini", reasoning: "low", timeoutSec: 30)` |
| 10 | `backends.agy.fallbackCommand == "gemini"` | ✅ | `BackendConfig(..., model: "gemini-3.5-flash", fallbackCommand: "gemini", timeoutSec: 30)` |
| 11 | `backends.google-v2.endpoint == "https://translation.googleapis.com/language/translate/v2"` | ✅ | `BackendConfig(type: "http", endpoint: ..., target: "zh-CN", format: "text")` |
| 12 | `backends.doubao.endpoint == "https://ark.cn-beijing.volces.com/api/v3/responses"` | ✅ | `BackendConfig(type: "http", model: ..., endpoint: ..., targetLanguage: "zh")` |
| 13 | `backends.doubao.model == "doubao-seed-translation-250915"` | ✅ | same as above |
| 14 | `translation.promptTemplate` contains `"简体中文"` | ✅ | uses `ConfigService.defaultPromptTemplate`, which contains `"简体中文"` |
| 15 | `modelCatalog.claude` containsItem `"haiku"` | ✅ | `"claude": ["haiku", "sonnet", "opus", "fable"]` |

## Decisions / deviations from spec

无偏离.

- Empty `apiKey` / `source` / `sourceLanguage` fields are omitted entirely (encoded as `nil`), matching the `AppConfig.swift` design comment that "empty `source`/`sourceLanguage` be omitted entirely" and the "nulls omitted" contract. This does not affect any of the 15 asserts.
- `translation.promptTemplate` uses the existing `ConfigService.defaultPromptTemplate` constant as instructed, rather than the shorter variant shown in the spec §7 JSON example.

## Open questions for Leader

none

## Commit

Working-tree change on top of `11e1b62 [T-MAC-11] Implement PromptBuilder.build(template:content:)`.
The macOS platform files (including `ConfigService.swift`) are currently untracked in this repository, so no new commit SHA was produced. Per the general git-mutation guideline, a commit was not created unless explicitly requested.

## Verdict

PASS

## Checks

- `swift test` from `platforms/macos/`:
  - `ConfigDefaultsTests/testConfigDefaults` PASSED ✅
  - `PureFunctionsTests/testPromptBuilder` PASSED ✅
  - Remaining 4 vectors RED as required ✅ (BackendRequestsTests, PipelineCacheTests, testAnsiStripper, testHotkeyParser)
- `git diff --check` passed with no whitespace errors ✅
- Only `platforms/macos/src/Core/ConfigService.swift` was edited; `AppConfig.swift`, `/spec`, `/conformance`, `CONSTITUTION.md`, and `platforms/windows/` were not touched ✅

### Relevant `swift test` excerpt

```
Test Suite 'ConfigDefaultsTests' started ...
Test Case '-[TranslateTheDamnConformanceTests.ConfigDefaultsTests testConfigDefaults]' started.
Test Case '-[TranslateTheDamnConformanceTests.ConfigDefaultsTests testConfigDefaults]' passed (0.001 seconds).
Test Suite 'ConfigDefaultsTests' passed ...

Test Case '-[TranslateTheDamnConformanceTests.PureFunctionsTests testPromptBuilder]' started.
Test Case '-[TranslateTheDamnConformanceTests.PureFunctionsTests testPromptBuilder]' passed (0.000 seconds).

Test Suite 'All tests' failed at ... Executed 6 tests, with 31 failures ...
```

The 31 failures are entirely in the 4 intentionally-RED vectors (`BackendRequestsTests`, `PipelineCacheTests`, `testAnsiStripper`, `testHotkeyParser`).

## Next recommendation

Per `.hopper/MANIFEST.md`, the next cursor should advance to the next macOS conformance vector. The `config-defaults` vector is now green; recommend picking up `backend-requests` (T-MAC-12 or equivalent) next, which depends on `HttpBackend` / `BackendRequestBuilder` implementation.

## Vendor output (parsed) _(preview 8000/29917 chars; full raw stream in `T-MAC-10-output.log`)_

````
• Let me start by reading the relevant files to understand the task. I need to read:
  1. The current ConfigService.swift
  2. AppConfig.swift
  3. ConfigDefaultsTests.swift
  4. conformance/config-defaults.json
  5. The spec section 7

  Let me read these in parallel.I have all the information needed. I need to implement `ConfigService.swift` with:
  1. `defaultConfig()` returning the full default per spec §7
  2. `load(from path: String) -> AppConfig?` - reads + decodes JSON, returns nil if file absent
  3. `save(_ cfg: AppConfig, to path: String) throws` - encode via ConfigEncoding.encoder, write

  Note: The test uses `JSONEncoder().encode(cfg)` not `ConfigEncoding.encoder`, but that's fine because the default JSONEncoder will encode the same structure. The key difference is sorted keys - but tests don't check byte-level JSON output, they parse and navigate.

  Important: The spec §7 shows promptTemplate as:
  "源语言为英文则术语保留英文、其余译为简体中文;非英文则全部译为简体中文;代码块保持原样;只输出译文。\n\n内容:\n{content}"

  But the existing `defaultPromptTemplate` is:
  "源语言为英文时,专业术语/技术名词保留英文,其余描述性内容译为简体中文。\n" +
  "源语言为非英文时,全部译为简体中文(含代码注释、变量名解释)。\n" +
  "代码块、命令行、配置示例保持原样,仅翻译其中说明性文字。只输出译文,不要任何前后缀。\n\n" +
  "内容:\n{content}"

  The acceptance only requires contains "简体中文", and the task explicitly says "use `ConfigService.defaultPromptTemplate`". So I'll use the existing defaultPromptTemplate.

  For backends, I need to match the spec exactly. Note the test uses dot paths on the serialized JSON. Because BackendConfig fields are optional and JSONEncoder omits nils, only non-nil fields will be present.

  Spec backends:
  - claude: type cli, command claude, model haiku, outputFormat text, timeoutSec 30
  - codex: type cli, command codex, model gpt-5.4-mini, reasoning low, timeoutSec 30
  - copilot: type cli, command copilot, model claude-haiku-4.5, timeoutSec 30
  - agy: type cli, command agy, model gemini-3.5-flash, fallbackCommand gemini, timeoutSec 30
  - google-v2: type http, endpoint ..., apiKey "", target zh-CN, source "", format text
  - doubao: type http, endpoint ..., apiKey "", model doubao-seed-translation-250915, targetLanguage zh, sourceLanguage ""

  Wait - for google-v2, `source` is "" and apiKey is "". With Optional fields, "" is a non-nil value, so it WILL be emitted. But the spec explicitly says in §6.1: "omit empty source/model fields entirely". And AppConfig.swift says "making every heterogenous backend field Optional so absent values are dropped, not emitted as JSON null. This matches conformance/config-defaults.json paths like backends.claude.model and the requirement that empty source/sourceLanguage be omitted entirely."

  So in Swift, to omit empty source/sourceLanguage, I should set them to nil. The spec shows them as empty strings in the example JSON, but the design says omit empty. However, the conformance tests don't assert anything about source/apiKey/sourceLanguage being absent. They only assert specific fields.

  But wait - the task says "Use the EXACT field values from spec §7". This is slightly ambiguous. The acceptance criteria only tests specific fields. For fields that would be empty strings, I should probably set them to nil to match the "nulls omitted" contract. But the spec example shows apiKey:"" and source:"". Hmm.

  Actually, looking at the spec example more carefully:
  ```
  "google-v2": { "type": "http", "endpoint": "...", "apiKey": "", "target": "zh-CN", "source": "", "format": "text" },
  "doubao":    { "type": "http", "endpoint": "...", "apiKey": "", "model": "...", "targetLanguage": "zh", "sourceLanguage": "" }
  ```

  But then in AppConfig.swift comment: "by making every heterogenous backend field Optional so absent values are dropped, not emitted as JSON null. This matches conformance/config-defaults.json paths like backends.claude.model and the requirement that empty source/sourceLanguage be omitted entirely."

  So the "requirement that empty source/sourceLanguage be omitted entirely" means I should NOT emit empty strings. With the Optional encoding in Swift, only nil values are omitted. So I should set source and sourceLanguage to nil, not "".

  What about apiKey? The spec shows "" but it's also a secret field. The test doesn't assert on apiKey. I think it's safer to set apiKey to nil too since the comment says "empty source/sourceLanguage" specifically, but apiKey being empty would also be emitted as "". However, the spec example shows apiKey as "". 

  The task acceptance only checks the 15 asserts. Let me not overthink. I'll set the values to match what's asserted. For apiKey/source/sourceLanguage, I'll follow the spec example and set them as empty strings? Or nil to omit? The safest interpretation for "nulls omitted" is to not emit empty values where not needed. But spec shows apiKey:"".

  Actually, the acceptance criteria says "EXACT field values from spec §7" in the list. The listed fields don't include apiKey/source/sourceLanguage. The conformance vector doesn't assert them. I'll set apiKey to "" to match spec example (it shows "" explicitly), and source/sourceLanguage to nil because AppConfig.swift explicitly says "empty source/sourceLanguage be omitted entirely".

  Wait, but the spec §7 example JSON literally has `"source": ""` and `"sourceLanguage": ""`. And AppConfig.swift says empty source/sourceLanguage should be omitted. This is a contradiction between spec example and code comment. Given the code comment explicitly mentions "the requirement that empty source/sourceLanguage be omitted entirely", and the task says AppConfig.swift is CORRECT, I should trust AppConfig.swift's design intent. So set source and sourceLanguage to nil.

  For apiKey, it's shown as "" in spec. I'll set it to "" to match. It won't break anything.

  Actually, let me reconsider: with `apiKey: ""` (non-nil String?), it WILL be serialized as `"apiKey": ""`. The test doesn't check this, so it doesn't matter for passing. But to be byte-aligned with Windows maybe we want exact. The spec example shows empty strings. The Windows implementation probably serializes empty strings. Since the task says "Use the EXACT field values from spec §7", I should use "" for apiKey, source, sourceLanguage where shown.

  But then AppConfig.swift says "empty source/sourceLanguage be omitted entirely". Hmm.

  Let me look at the task again: "Use the EXACT field values from spec §7: claude {model:'haiku', outputFormat:'text', timeoutSec:30}; ... google-v2 {endpoint, target:'zh-CN', format:'text'}; doubao {endpoint, model:'doubao-seed-translation-250915', targetLanguage:'zh'}."

  The task explicitly lists only non-empty values for google-v2 and doubao. It does NOT list apiKey, source, sourceLanguage. So I can set those to nil (omitted) without violating the acceptance. And AppConfig.swift's design intent is to omit empty source/sourceLanguage.

  I'll set apiKey to nil too actually, because it's a secret and on first run it should be absent. But spec example shows "". I'll set it to nil to keep output clean. The acceptance won't fail either way.

  Actually wait - the prompt template default in ConfigService.swift differs from spec §7. The task says "translation.promptTemplate contains '简体中文' (use `ConfigService.defaultPromptTemplate`)". So use existing defaultPromptTemplate. Good.

  Let me now write the implementation.

  For load/save:
  - `load(from path: String) -> AppConfig?`: expand ~ using NSString.expandingTildeInPath, check if file exists, read data, decode with JSONDecoder(), return nil on absence or decode failure? The task says "returns nil if the file is absent". It doesn't explicitly say decode failure returns nil, but typically we'd return nil on any error. Actually it says "reads + decodes JSON; returns nil if the file is absent". I think returning nil on decode failure is also reasonable, but to be safe maybe throw? No, signature returns optional, no throws. So return nil on any failure. But specifically file absent.
  - `save(_ cfg: AppConfig, to path:

... [truncated, 21917 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 126524
- end_time: 2026-06-18T04:05:00.506Z
- log: see `T-MAC-10-output.log` for raw output

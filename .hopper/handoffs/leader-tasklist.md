# Leader tasklist — translate-the-damn macOS port

Detailed per-task specs. `hopper-dispatch <task-id>` extracts the `## <task-id>` section below (up
to the next H2) and composes it with the task-type frame + governance into the vendor prompt.

**Constitution gates (apply to every task below)**: Law 1 spec-first (treat `/spec`, `/conformance`
read-only); Law 2 vectors are the truth; Law 6 backends read `spec/backends.json` (never hardcode).
Edit ONLY under `platforms/macos/`. Do NOT touch `/spec`, `/conformance`, `CONSTITUTION.md`, `docs/`,
or `platforms/windows/`. Native Swift, Foundation only, zero external deps. Run `swift test` from
`platforms/macos/` (or `swift test --package-path platforms/macos`) and report the EXACT output; do
not claim pass unless the test actually passes. Report `git diff --stat` to prove scope.

---

## T-MAC-11

**Task-type**: code-impl  **Vendor**: kimi (default `kimi-code/kimi-for-coding`)  **Deps**: T-MAC-02 (done)

### Goal
Implement `PromptBuilder.build(template:content:)` in
`platforms/macos/src/Core/PromptBuilder.swift` (currently a stub returning `""`) so the
`prompt-builder` conformance vector passes. After your change, `swift test` must show
`PureFunctionsTests/testPromptBuilder` PASSED — and the other 5 vectors still RED (do not touch them).

### Background (read; do not modify any of these)
- `conformance/prompt-builder.json` — the 4 golden cases (the exact contract you must satisfy).
- `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md` §5 (prompt rules + the default
  template, which uses `{content}`).
- `platforms/macos/src/Core/PromptBuilder.swift` — the stub to replace.
- `platforms/macos/tests/Conformance/PureFunctionsTests.swift` — how the runner calls the function
  (`PromptBuilder.build(template:content:)`) and asserts exact string equality against `out`.

### Acceptance (exact — the 4 cases in `conformance/prompt-builder.json`)
1. `template="rules: {content}"`, `content="hello"`  → `"rules: hello"`
2. `template=""`,                  `content="hello"`  → `"hello"`
3. `template="just rules"`,        `content="hello"`  → `"just rules\n\nhello"`
4. `template="X {content}"`,       `content="你好"`    → `"X 你好"`

Semantics:
- If the template contains the literal placeholder `{content}`, substitute the **first** occurrence
  with `content`.
- If the template is empty (`""`), return `content` unchanged.
- If the template is non-empty and has NO `{content}` placeholder, return `template + "\n\n" + content`.
- Cases 2 and 3 are consistent with the above (empty ⇒ content; non-empty-no-placeholder ⇒ append).

### Return
- The implemented `platforms/macos/src/Core/PromptBuilder.swift`.
- The EXACT `swift test` output showing `testPromptBuilder` PASSED and the other tests still failing
  (RED) — proving you flipped only this one vector.
- `git diff --stat` confirming ONLY `PromptBuilder.swift` was edited.

### Constraints
- Edit ONLY `platforms/macos/src/Core/PromptBuilder.swift`.
- Keep the signature `public static func build(template: String, content: String) -> String`.
- Native Swift, Foundation only. No external dependencies.
- Do NOT modify the runner, other stubs, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Run `swift test` from `platforms/macos/`; report the real output. Do not claim pass unless it passes.

---

## T-MAC-10

**Task-type**: code-impl  **Vendor**: kimi (default `kimi-code/kimi-for-coding`)  **Deps**: T-MAC-02 (done)

### Goal
Implement `ConfigService.defaultConfig()` (plus `load`/`save`) in
`platforms/macos/src/Core/ConfigService.swift` so the `config-defaults` conformance vector passes.
After your change, `swift test` must show `ConfigDefaultsTests/testConfigDefaults` PASSED. The
`prompt-builder` vector (already green) must STAY green; the other 4 vectors stay RED — do not touch them.

### Background (read; do not modify)
- `conformance/config-defaults.json` — the 15 `assert[]` entries (the exact contract).
- `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md` §7 — the full default config.json
  (6 backends, modelCatalog, every field value). This is your source of truth for the values.
- `platforms/macos/src/Core/ConfigService.swift` — the stub (`AppConfig(version: 0, backends: [:], …)`).
- `platforms/macos/src/Core/AppConfig.swift` — the `AppConfig`/`BackendConfig`/sub-config Codable structs
  (CORRECT — do NOT change them). `BackendConfig` fields are all optional; `type` ("cli"|"http")
  disambiguates. `ConfigEncoding.encoder` is camelCase + sortedKeys + nulls-omitted.
- `platforms/macos/tests/Conformance/ConfigDefaultsTests.swift` — serializes `defaultConfig()` and
  applies the assert ops (equals/count/contains/containsItem) via dot-path navigation.

### Acceptance (exact — satisfy ALL 15 asserts in `conformance/config-defaults.json`)
`version`==1 · `general.activeBackend`=="claude" · `general.listenClipboard`==true ·
`hotkey.translate`=="Ctrl+Alt+T" · `popup.style`=="acrylic" · `popup.autoDismissSeconds`==6 ·
`backends` count==6 (claude, codex, copilot, agy, google-v2, doubao) · `backends.claude.model`=="haiku" ·
`backends.codex.reasoning`=="low" · `backends.agy.fallbackCommand`=="gemini" ·
`backends.google-v2.endpoint`=="https://translation.googleapis.com/language/translate/v2" ·
`backends.doubao.endpoint`=="https://ark.cn-beijing.volces.com/api/v3/responses" ·
`backends.doubao.model`=="doubao-seed-translation-250915" ·
`translation.promptTemplate` contains "简体中文" (use `ConfigService.defaultPromptTemplate`) ·
`modelCatalog.claude` containsItem "haiku".

Use the EXACT field values from spec §7: claude {model:"haiku", outputFormat:"text", timeoutSec:30};
codex {model:"gpt-5.4-mini", reasoning:"low", timeoutSec:30}; copilot {model:"claude-haiku-4.5", timeoutSec:30};
agy {model:"gemini-3.5-flash", fallbackCommand:"gemini", timeoutSec:30};
google-v2 {endpoint, target:"zh-CN", format:"text"}; doubao {endpoint, model:"doubao-seed-translation-250915", targetLanguage:"zh"}.
modelCatalog: claude [haiku,sonnet,opus,fable]; codex [gpt-5.4-mini,gpt-5.4,gpt-5.5];
copilot [claude-haiku-4.5,claude-sonnet-4.6,gpt-5.4,gemini-3.5-flash]; agy [gemini-3.5-flash,gemini-3.1-pro];
google-v2 [nmt]; doubao [doubao-seed-translation-250915]. `general.startWithWindows`=false, `hotkey.toggleListen`="",
`popup.keepOnHover`=true, `popup.position`="top-center", `translation.targetLanguageDefault`="zh-CN", `translation.maxChars`=8000.

ALSO implement (for M3 use; NOT vector-asserted): `ConfigService.load(from path: String) -> AppConfig?`
(reads + decodes JSON; returns nil if the file is absent) and `ConfigService.save(_ cfg: AppConfig, to path: String) throws`
(encode via `ConfigEncoding.encoder` → write). Default path `~/.translatethedamn/config.json` (expand `~`).

### Return
- The implemented `platforms/macos/src/Core/ConfigService.swift`.
- EXACT `swift test` output: `testConfigDefaults` PASSED, `testPromptBuilder` PASSED, other 4 RED.
- `git diff --stat` confirming ONLY `ConfigService.swift` edited.

### Constraints
- Edit ONLY `platforms/macos/src/Core/ConfigService.swift`.
- Do NOT modify `AppConfig.swift` (structs are correct), the runner, other stubs, `/spec`, `/conformance`,
  `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, Foundation only. Run `swift test` from `platforms/macos/`; report real output.
- Do not claim pass unless the test actually passes.

---

## T-MAC-12

**Task-type**: code-impl  **Vendor**: kimi (default `kimi-code/kimi-for-coding`)  **Deps**: T-MAC-02 (done)

### Goal
Implement `AnsiStripper.strip(_ s: String) -> String` in
`platforms/macos/src/Core/AnsiStripper.swift` so the `ansi-stripper` conformance vector passes. After
your change, `swift test` must show `PureFunctionsTests/testAnsiStripper` PASSED. `prompt-builder` +
`config-defaults` stay green; the other 3 vectors stay RED — do not touch them.

### Background (read; do not modify)
- `conformance/ansi-stripper.json` — 5 golden cases. NOTE: inputs use printable markers `<ESC>` (=0x1B)
  and `<CR>` (=0x0D); the runner substitutes these to real bytes BEFORE calling `strip` (see
  `ConformanceHarness.substituteMarkers` in the test dir). So `strip` receives real ESC/CR bytes, not tokens.
- `platforms/macos/src/Core/AnsiStripper.swift` — the stub (returns `""`).
- `platforms/macos/tests/Conformance/PureFunctionsTests.swift` — calls
  `AnsiStripper.strip(ConformanceHarness.substituteMarkers(raw))` and asserts exact equality vs `out`.
- Windows reference: `platforms/windows/src/` AnsiStripper (regex intent) — read-only.

### Acceptance (exact — the 5 cases in `conformance/ansi-stripper.json`)
1. `<ESC>[31mhello<ESC>[0m` → `hello`          (strip SGR colour: ESC[…m)
2. `a<CR>b` → `ab`                              (strip carriage return \r)
3. `plain` → `plain`                            (no escapes; untouched)
4. `` → ``                                      (empty stays empty)
5. `<ESC>[2K<ESC>[1Gdone` → `done`             (strip cursor clear/move: ESC[2K, ESC[1G)

Semantics: remove ANSI escape sequences — CSI (`ESC [` + parameter/intermediate bytes + a final byte
0x40–0x7E, e.g. `m`,`K`,`G`,`H`), OSC (`ESC ]`… terminated by BEL `\x07` or ST `ESC \`), and other
`ESC <X>` two-byte sequences — AND remove all carriage returns (`\r`). Leave other characters
(including `\n`) intact. Robust regex: `\u{1B}\[[0-9;?]*[A-Za-z]` (CSI) + `\u{1B}\][^\x07]*(\x07|\u{1B}\\)`
(OSC) + `\u{1B}.` (other ESC) + `\r`.

### Return
- The implemented `platforms/macos/src/Core/AnsiStripper.swift`.
- EXACT `swift test` output: `testAnsiStripper` PASSED; `testPromptBuilder` + `testConfigDefaults` still PASSED.
- `git diff --stat` confirming ONLY `AnsiStripper.swift` edited.

### Constraints
- Edit ONLY `platforms/macos/src/Core/AnsiStripper.swift`.
- Do NOT modify the runner, other stubs, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, Foundation only. Run `swift test` from `platforms/macos/`; report real output.
- Do not claim pass unless the test actually passes.

---

## T-MAC-13

**Task-type**: code-impl  **Vendor**: opencode (model `tokenbox/deepseek-v4-pro`; opencode ignores `--reasoning`)  **Deps**: T-MAC-02 (done)

### Goal
Implement `HotkeyParser.parse(_ text: String) -> HotkeyResult` in
`platforms/macos/src/Core/HotkeyParser.swift` so the `hotkey-parser` conformance vector passes. After
your change, `swift test` must show `PureFunctionsTests/testHotkeyParser` PASSED. The already-green
vectors (prompt-builder, ansi-stripper, config-defaults) stay green; the other 2 (backend-requests,
pipeline-cache) stay RED — do not touch them.

### Background (read; do not modify)
- `conformance/hotkey-parser.json` — 6 golden cases. `out` asserts a SUBSET of `HotkeyResult` fields
  (extra native fields ignored). `virtualKey` is the **Win32 VK code** (NOT a macOS keycode):
  'T'=84, F2=113, Space=32.
- `platforms/macos/src/Core/HotkeyParser.swift` — the stub + `HotkeyResult` struct (isValid, hasControl,
  hasAlt, hasWin, hasShift: Bool; virtualKey: Int; display: String). The struct is CORRECT; implement `parse`.
- `platforms/macos/tests/Conformance/PureFunctionsTests.swift` — calls `HotkeyParser.parse(text)` and
  asserts each field present in `out`.

### Acceptance (exact — the 6 cases in `conformance/hotkey-parser.json`)
1. "Ctrl+Alt+T"      → isValid=true, hasControl=true, hasAlt=true, virtualKey=84, display="Ctrl+Alt+T"
2. "Ctrl+F2"         → isValid=true, virtualKey=113
3. "Win+Shift+Space" → isValid=true, hasWin=true, hasShift=true, virtualKey=32
4. "T"               → isValid=false        (bare key, no modifier ⇒ invalid)
5. ""                → isValid=false        (empty ⇒ invalid)
6. "Ctrl+Foo"        → isValid=false        (unknown key ⇒ invalid)

Semantics:
- Split on '+'. Each token is a modifier (Ctrl/Control, Alt, Win/Super/Command/Cmd, Shift) or the final
  key. At least one modifier is REQUIRED (bare key ⇒ invalid). The final token must be a recognized key.
- Recognized keys: A–Z (VK = uppercase ASCII, 'A'=65…'Z'=90, so 'T'=84), F1–F24 (F1=112, F2=113, …
  F_n=111+n), Space (32), digits '0'–'9' (VK 48–57). Unknown key ⇒ invalid. Case-insensitive parsing.
- `virtualKey` = the Win32 VK code of the final key.
- `display` = normalized form "Ctrl+Alt+T" (modifiers in canonical order Ctrl, Alt, Shift, Win, then the
  key title-cased). Match the vector's expected `display` exactly for case 1.
- For invalid input return `isValid=false` (other fields not asserted by the vector).

NOTE: a VK→macOS keycode map (for Carbon `RegisterEventHotKey` in M3) is a SEPARATE concern (T-MAC-31),
NOT part of this task. Implement the parser only.

### Return
- The implemented `platforms/macos/src/Core/HotkeyParser.swift` (the `parse` func; do NOT change `HotkeyResult`).
- EXACT `swift test` output: `testHotkeyParser` PASSED; prompt-builder/ansi-stripper/config-defaults still PASSED.
- `git diff --stat` confirming ONLY `HotkeyParser.swift` edited.

### Constraints
- Edit ONLY `platforms/macos/src/Core/HotkeyParser.swift`.
- Do NOT modify the runner, other stubs, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, Foundation only. Run `swift test` from `platforms/macos/`; report real output.
- Do not claim pass unless the test actually passes.

---

## T-MAC-14

**Task-type**: code-impl  **Vendor**: opencode (model `tokenbox/deepseek-v4-pro`; pass `--sandbox danger-full-access`)  **Deps**: T-MAC-02 (done)

### Goal
Implement the **backend manifest interpreter** — a generic engine that reads `spec/backends.json` at
runtime (Constitution Law 6: backends are data, NEVER hardcode) — so the `backend-requests` conformance
vector passes. After your change, `swift test` must show `BackendRequestsTests/testBackendRequests`
PASSED. The 4 already-green vectors stay green; `pipeline-cache` stays RED — do not touch it.

This is the most important M2 task: it's the whole point of the manifest-driven design (Law 6). The
Windows `ManifestEngine` is the reference; port its behaviour, not its code.

### Background (read; do not modify)
- `spec/backends.json` — the declarative manifest (single source for HOW each backend is called). Read
  it at runtime; do NOT copy its values into code.
- `conformance/backend-requests.json` — 4 golden cases (the exact request shapes to produce).
- `platforms/macos/src/Core/HttpBackend.swift` — stub: `struct HttpCall {method,url,headers,body}`,
  `BackendTestConfig` (Codable; apiKey/target/source/format/model/targetLanguage/endpoint/sourceLanguage),
  `HttpBackend.buildCall(backend:config:text:) -> HttpCall` (stub returns empty).
- `platforms/macos/tests/Conformance/BackendRequestsTests.swift` — decodes each case's `config` into
  `BackendTestConfig`, calls `buildCall`, asserts method/urlContains/urlNotContains/headers/bodyContains/bodyNotContains.
- Windows reference: `platforms/windows/src/` — `ManifestEngine` (placeholder subst, bodyTemplate,
  omitWhenEmpty, responsePath). Read-only; port the behaviour.

### Acceptance (exact — the 4 cases in `conformance/backend-requests.json`)
1. google-v2, config {apiKey:"K", target:"zh-CN", format:"text"}, text "Hello" → POST; url ∋ "translate/v2";
   header x-goog-api-key="K"; body ∋ `"q":"Hello"`,`"target":"zh-CN"`,`"format":"text"`; body ∌ "source".
2. google-v2, config {apiKey:"K", source:"en"}, text "Hi" → body ∋ `"source":"en"`.
3. google-v2, config {apiKey:"K", target:""}, text "Hi" → body ∋ `"target":"zh-CN"` (empty ⇒ manifest default).
4. doubao, config {apiKey:"K", model:"doubao-seed-translation-250915", targetLanguage:"zh"}, text "Hello" →
   POST; url ∋ "/responses"; url ∌ "chat/completions"; header Authorization="Bearer K";
   body ∋ "input_text",`"target_language":"zh"`,`"model":"doubao-seed-translation-250915"`; body ∌ "source_language","messages".

Semantics (port from `spec/backends.json` + Windows ManifestEngine):
- Load `spec/backends.json` by walking up to the repo root (like the conformance harness). Cache it.
- For an http backend: method = manifest `method`; url = manifest `endpoint`; headers = manifest `headers`
  with placeholders (`{apiKey}`) substituted from config; body = serialize manifest `bodyTemplate` with
  placeholders (`{text}`,`{target}`,`{format}`,`{source}`,`{model}`,`{targetLanguage}`,`{sourceLanguage}`)
  substituted from config, then drop keys in `omitWhenEmpty` whose value is empty/absent.
- Manifest `defaults` fill missing config (google-v2 target⇒"zh-CN", format⇒"text"; doubao
  model⇒"doubao-seed-translation-250915", targetLanguage⇒"zh"). Config overrides defaults.
- Body MUST be COMPACT JSON (no spaces) so `"q":"Hello"` (not `"q": "Hello"`) matches `bodyContains`.
- Keep `buildCall(backend: String, config: BackendTestConfig, text: String) -> HttpCall`.

ALSO implement (for M3, NOT vector-asserted — add unit tests in `tests/`): a `responsePath` evaluator
that extracts translated text from a response JSON given the manifest `responsePath`:
- dot + index: `data.translations[0].translatedText`.
- array filter: `output[type=message].content[type=output_text].text` — in array `output` find element
  with `type=="message"`, then in its `content` array find `type=="output_text"`, take `.text` (don't
  assume `output[0]`). A small parser for `[index]` and `[key=value]` segments.

### Return
- The interpreter in `platforms/macos/src/Core/HttpBackend.swift` and/or a new `BackendManifest.swift`.
- New unit tests for responsePath in `platforms/macos/tests/` (NOT a conformance vector).
- EXACT `swift test` output: `testBackendRequests` PASSED; 4 green vectors still PASSED; `pipeline-cache` RED.
- `git diff --stat` confirming only `platforms/macos/` files edited.

### Constraints
- Read `spec/backends.json` at runtime — do NOT hardcode endpoints/headers/body shapes (Law 6).
- Edit ONLY under `platforms/macos/`. Do NOT modify the runner, other stubs, `/spec`, `/conformance`,
  `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, Foundation only. Run `swift test` from `platforms/macos/`; report real output.
- Do not claim pass unless the test actually passes.

---

## T-MAC-15

**Task-type**: code-impl  **Vendor**: opencode (model `tokenbox/deepseek-v4-pro`; pass `--sandbox danger-full-access`)  **Deps**: T-MAC-02 (done)

### Goal
Implement the one-entry "last successful translation" cache in
`platforms/macos/src/Core/TranslationPipeline.swift` so the `pipeline-cache` conformance vector passes
(the LAST RED vector). After your change, `swift test` must show ALL 6 vectors PASSED (0 failures) —
M2 core logic complete. Do not touch the 5 already-green vectors.

### Background (read; do not modify)
- `conformance/pipeline-cache.json` — 1 scenario, 5 steps. Stateful: replay steps through a FRESH
  pipeline + a fake translator; `expectModelCall=true` ⇒ model invoked (cache miss); `false` ⇒ served
  from cache (no model call). Cache key = text + backend + model; only SUCCESSFUL results are cached.
- `platforms/macos/src/Core/TranslationPipeline.swift` — the stub: `Translator` protocol
  (`translate(text:model:) -> TranslationResult`), `TranslationResult` (ok/text), `TranslationPipeline`
  with `init(backend:translator:)` + `run(text:model:) -> TranslationResult`. The stub always calls the
  translator (cache never consulted) so `expectModelCall:false` steps fail RED.
- `platforms/macos/tests/Conformance/PipelineCacheTests.swift` — per scenario, FRESH pipeline +
  FakeTranslator (records `calls`); for each step, measures `fake.calls` delta before/after `run`;
  asserts delta == (expectModelCall ? 1 : 0).
- Windows reference: `platforms/windows/src/` TranslationPipeline cache — read-only.

### Acceptance (exact — the scenario in `conformance/pipeline-cache.json`)
Scenario "same text+model hits; model/text change forces re-translate", backend "fake", steps:
1. text="same", model="m1" → expectModelCall=true  (miss: first call)
2. text="same", model="m1" → expectModelCall=false (HIT: same text+backend+model ⇒ cached ⇒ no model call)
3. text="same", model="m2" → expectModelCall=true  (miss: model changed ⇒ different key)
4. text="other", model="m2" → expectModelCall=true (miss: text changed ⇒ different key)
5. text="other", model="m2" → expectModelCall=false (HIT: same text+model ⇒ cached)

Semantics:
- In `run(text:model:)`: compute cache key = (text, backend, model). If the cached entry's key matches ⇒
  return the cached `TranslationResult` WITHOUT calling the translator (delta=0).
- Otherwise call `translator.translate(text:model:)`. If `result.ok == true` ⇒ store it in the one-entry
  cache (key = text+backend+model). If `ok == false` ⇒ do NOT cache (a retry must hit the model again).
- The cache holds ONE entry (the last successful translation); a different key replaces it.
- `backend` is the pipeline's fixed backend (set at `init`); `model` is the per-run arg. Effective key =
  (text, self.backend, model).
- The test's FakeTranslator returns successful results (so they cache). Do NOT change `Translator`,
  `TranslationResult`, or the test's FakeTranslator — only `TranslationPipeline.run`.

### Return
- The implemented `platforms/macos/src/Core/TranslationPipeline.swift` (the `run` func + cache logic).
- EXACT `swift test` output: ALL 6 tests PASSED, 0 failures (whole suite green — M2 core logic complete).
- `git diff --stat` confirming ONLY `TranslationPipeline.swift` edited.

### Constraints
- Edit ONLY `platforms/macos/src/Core/TranslationPipeline.swift` (the `run` func + CacheEntry logic; do
  NOT change `Translator`/`TranslationResult`/`init` signatures).
- Do NOT modify the runner, other stubs, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, Foundation only. Run `swift test` from `platforms/macos/`; report real output.
- Do not claim pass unless all 6 vectors are actually green.

---

## T-MAC-16

**Task-type**: code-impl  **Vendor**: kimi (default `kimi-code/kimi-for-coding`)  **Deps**: T-MAC-10 (done)

### Goal
Implement `PathResolver` for macOS — resolve a CLI command name (e.g. "claude", "agy") to an executable
path, handling the **GUI PATH gotcha** (an app launched from Finder gets a minimal PATH and can't find
Homebrew/nvm-installed CLIs). There is NO conformance vector for this (it's OS/IO); acceptance = unit
tests you write. After your change, `swift test` must still show all 6 conformance vectors PASSED (0
failures) — do not break them — PLUS your new PathResolverTests PASSED.

### Background (read; do not modify)
- `docs/PORTING-macos.md` — "GUI PATH gotcha" + "Core adaptation checklist" (PathResolver POSIX branch:
  execute-bit check, knownInstallPaths, login-shell PATH).
- Verified CLI install paths on THIS machine (`hopper-dispatch --check`): codex/opencode/mimo in
  `~/.nvm/versions/node/v22.22.3/bin/`; copilot in `/opt/homebrew/bin/`; agy in `~/.local/bin/`; kimi in
  `~/.kimi-code/bin/`; grok in `~/.grok/bin/`.
- `platforms/macos/CLAUDE.md` — the knownInstallPaths list to bake in.
- Windows reference: `platforms/windows/src/` PathResolver — read-only (port the contract: walk PATH; on
  POSIX no PATHEXT, check the binary directly + execute-bit; fall back to knownInstallPaths; the
  .cmd/.ps1 wrapping is Windows-only — POSIX returns the binary directly).

### Acceptance (unit tests YOU write in `platforms/macos/tests/PathResolverTests.swift`)
Implement `PathResolver` (new file `platforms/macos/src/Core/PathResolver.swift`) with:
- `resolve(_ command: String) -> String?` — absolute path to the executable, or nil.
- Resolution order: (1) search `PATH` env dirs for an executable `command`; (2) if not found, search
  `knownInstallPaths` (injectable per-OS): on macOS include `/opt/homebrew/bin`, `/usr/local/bin`,
  `~/.nvm/versions/node/*/bin` (glob node version dirs), `~/.local/bin`, `~/.kimi-code/bin`,
  `~/.grok/bin`, `~/.npm-global/bin`; (3) if still not found, read login-shell PATH once
  (`zsh -ilc 'echo $PATH'`) and re-search.
- POSIX execute-bit check: a candidate is valid only if `FileManager.isExecutableFile` (or `access(X_OK)`).
- Make knownInstallPaths + the login-shell-PATH reader INJECTABLE (so tests stub them without spawning a
  shell): e.g. `PathResolver(knownDirs: [String], extraPathProvider: () -> [String])`.
Unit tests (XCTest): (a) found on PATH; (b) found in knownInstallPaths when not on PATH; (c) execute-bit
respected (non-executable file with the right name is NOT returned); (d) not-found ⇒ nil; (e) injection
works. Use temp dirs + dummy executables (chmod +x) for deterministic tests (don't depend on installed CLIs).

### Return
- New `platforms/macos/src/Core/PathResolver.swift` + `platforms/macos/tests/PathResolverTests.swift`.
- EXACT `swift test` output: all 6 conformance vectors PASSED + PathResolverTests PASSED.
- `git diff --stat` confirming only platforms/macos/ files added/edited.

### Constraints
- Add ONLY `platforms/macos/src/Core/PathResolver.swift` + `platforms/macos/tests/PathResolverTests.swift`.
- Do NOT modify the runner, existing stubs/impls, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, Foundation only (FileManager; `Process`/`zsh` only inside the injectable login-shell reader).
- Run `swift test` from `platforms/macos/`; report real output. Do not claim pass unless tests pass.

---

## T-MAC-20

**Task-type**: code-review-adversarial  **Vendor**: mimo (model `xiaomi/mimo-v2.5-pro`, `--reasoning xhigh` → `--variant max`; review-tier gets the extended timeout floor)  **Deps**: T-MAC-10..16 (all M2 code-impl done)

### Goal
Adversarial cross-review of the M2 core logic (all of `platforms/macos/src/Core/*.swift`) against the
conformance vectors, the design spec, the Windows reference, and Swift correctness. You are a DIFFERENT
channel than the builders (kimi + opencode) — find what they missed. Output a review verdict + findings.
Do NOT edit code (review-only — read-only sandbox is correct for this task).

### Background (read; do not modify any code)
- `platforms/macos/src/Core/` — all M2 impls: PromptBuilder, AnsiStripper, HotkeyParser, AppConfig,
  ConfigService, HttpBackend (+ BackendManifest if present), TranslationPipeline, PathResolver.
- `conformance/*.json` — the 6 golden vectors (the contracts).
- `spec/backends.json` — the manifest (T-MAC-14 MUST read this at runtime; verify it doesn't hardcode).
- `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md` — behaviour spec (§5 prompt, §6
  backends, §7 config, §4.1 pipeline/cache).
- `platforms/windows/src/` — the reference impl (compare behaviour: ManifestEngine, pipeline cache, PathResolver).
- `CONSTITUTION.md` — Laws (esp. Law 2 vectors-are-truth, Law 6 backends-as-data).

### Acceptance (review output — write to `.hopper/handoffs/T-MAC-20-output.md`)
A structured review with:
- **Verdict**: one of PASS / PASS_WITH_CHANGES / REWORK.
- **Findings**, each: severity (P0/P1/P2), file:line, what's wrong, suggested fix. Focus on:
  1. **Vector-faithfulness**: does each impl match the vector SEMANTICS (not just pass the cases)? Edge
     cases the vectors don't cover (empty, unicode, long input, repeated placeholders, ANSI edge cases,
     hotkey case-insensitivity, cache key on failed translations).
  2. **Law 6**: does T-MAC-14 (HttpBackend/BackendManifest) actually READ `spec/backends.json` at
     runtime, or hardcode backend shapes? (Hardcoding = P0.)
  3. **Swift correctness**: force-unwraps, encoding (camelCase/nulls-omitted/sortedKeys for config),
     optionals, compact-JSON for request bodies, responsePath `[key=value]` filter correctness.
  4. **Cross-platform parity**: does behaviour match the Windows reference (cache key, status taxonomy,
     prompt subst rules, ANSI strip scope)?
  5. **PathResolver**: execute-bit check, GUI-PATH knownInstallPaths, injection for testability.
- Do NOT edit any code. Read-only except writing the review output.

### Return
- The review output.md (verdict + findings table).
- DO NOT modify `platforms/macos/`, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.

### Constraints
- Review-only. No code edits. Output only `.hopper/handoffs/T-MAC-20-output.md`.
- Read-only sandbox is correct here (this is a review task).

---

## T-MAC-20F

**Task-type**: code-impl  **Vendor**: opencode (model `tokenbox/deepseek-v4-pro`; pass `--sandbox danger-full-access`)  **Deps**: T-MAC-20 (mimo review done)

### Goal
Fix the must-fix findings from the mimo adversarial review (T-MAC-20). After your change, `swift test` must STILL show all 22 tests PASSED (0 failures) — do NOT break any conformance vector or existing test. These are robustness/correctness fixes; the 6 vectors + 10 manifest + 6 PathResolver tests must stay green.

### Fixes (exact)

**F1 — `BackendManifest.swift` `fatalError` → graceful** (lines ~16, 23): `load()` currently `fatalError`s if `spec/backends.json` is missing or unparseable. Replace with graceful failure: return an empty manifest (`["backends": [:]]`) + log to stderr (`print` or `os_log`). NEVER crash the app. (Defense-in-depth — the manifest normally exists.)

**F2 — `BackendManifest.swift` thread-safe cache** (line ~4): `nonisolated(unsafe) static var cachedManifest` has a first-load data race. Replace with a thread-safe lazy init — `OSAllocatedUnfairLock<[String:Any]?>` (or a `DispatchQueue` barrier, or an `actor`). Safe for concurrent first access.

**F3 — `ConfigService.swift` corrupt-config data loss** (`load`, line ~98): `try? JSONDecoder().decode(...)` returns nil on corrupt JSON ⇒ caller treats as "no config" ⇒ `save()` overwrites the user's file with defaults (permanent data loss). Fix: in `load(from:)`, if the file EXISTS but decode FAILS, rename the corrupt file to `<path>.bak` (preserve user data) + return `defaultConfig()` (recover with defaults without destroying the corrupt file). If the file is ABSENT, return nil (existing behavior).

**F8 — `ConfigService.swift` EnsureDefaults on load**: after decoding (or when returning defaultConfig on corrupt), deep-merge with `defaultConfig()` for any missing top-level keys / empty sub-objects (keep user values, fill missing defaults — esp. `backends`, `modelCatalog`). Mirrors the Windows `EnsureDefaults` parity.

**F4 + F5 — `PathResolver.swift` `Process` deadlock + no timeout** (`defaultLoginShellPathProvider`, lines ~106-132):
- DEADLOCK: `task.waitUntilExit()` is called BEFORE `readDataToEndOfFile()`. If the child fills the pipe buffer (~64KB) ⇒ deadlock. Fix: read stdout concurrently with `waitUntilExit` — read in a `DispatchQueue.global().async` block (or use `readabilityHandler`), THEN `waitUntilExit()`, THEN collect the data. The read must overlap the wait.
- TIMEOUT: add a ~5s timeout. If `zsh -ilc` doesn't exit within 5s (broken `.zshrc` / interactive prompt), `task.terminate()` + return `[]`. Use `DispatchSemaphore.wait(timeout:)` or a `DispatchQueue.asyncAfter` watchdog.

**F14/F15/F16 — stale "M1 STUB" doc comments**: delete the stale "M1 STUB" / "TODO(M2)" comment blocks in:
- `TranslationPipeline.swift` (lines ~28-31 "M1 STUB: the cache is never consulted" + the `// TODO(M2)` line ~45).
- `PromptBuilder.swift` (line ~10 "M1 STUB: returns `""`").
- `HotkeyParser.swift` (lines ~36-37 "M1 STUB: returns HotkeyResult()").
Replace with an accurate one-line doc comment or just remove the stale lines.

### NOT in scope (adjudicated — do NOT do these)
- DEFER to M3/M4: F6 (Codable `BackendDefinition` refactor), F7 (HttpCall `Result`-type), F10 (multi-char hotkey keys), F11 (AnsiStripper `s.count` perf), F12 (ESC `(` edge), F13 (pipeline cache thread-safety — M3 wiring).
- F9 (PromptBuilder single-replace): NOT a bug — the vector case 4 explicitly specs first-only. Leave as-is.
- F17 (rename `startWithWindows`): REJECT — Law 4 (config schema sacred + shared across platforms). Keep `startWithWindows`; macOS maps it to `SMAppService` at the App layer (M3).

### Return
- The edited files (BackendManifest.swift, ConfigService.swift, PathResolver.swift, PromptBuilder.swift, HotkeyParser.swift, TranslationPipeline.swift).
- EXACT `swift test` output: all 22 tests PASSED (0 failures) — no regression.
- `git diff --stat` confirming only `platforms/macos/src/Core/` files edited.

### Constraints
- Edit ONLY the listed files under `platforms/macos/src/Core/`.
- Do NOT modify the conformance runner, tests, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Do NOT change any public signature the conformance runner depends on (`buildCall`, `defaultConfig`, `parse`, `strip`, `build`, `run`, `resolve` must stay callable with the same types).
- Native Swift, Foundation only (`OSAllocatedUnfairLock`/`DispatchQueue`/`os_log` are fine). Run `swift test`; report real output. Do not claim pass unless 22/22 green.

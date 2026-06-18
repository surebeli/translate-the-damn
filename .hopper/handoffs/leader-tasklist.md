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

---

## T-MAC-29

**Task-type**: code-impl  **Vendor**: kimi (default `kimi-code/kimi-for-coding`)  **Deps**: T-MAC-20F (M2 done)

### Goal
Add the macOS **App executable target** to the SwiftPM package — the AppKit/SwiftUI app shell that M3's native components (clipboard/hotkey/popup/tray/settings) plug into. After this, `swift build` produces a runnable macOS menu-bar app executable (an empty shell: launches `NSApplication`, accessory activation policy = no Dock icon, a minimal main menu with Quit), and `swift test` stays 22/22 green. This is structural setup for M3 (like M1's scaffold) — no feature logic yet.

### Background (read; do not modify)
- `platforms/macos/Package.swift` — currently has `TranslateTheDamnCore` (lib) + `TranslateTheDamnConformanceTests`. Add an executable target.
- `platforms/macos/CLAUDE.md` — stack (Swift SwiftUI+AppKit, arm64, macOS 14, no App Sandbox).
- `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md` §3 — architecture: single long-running tray process, NO main window (menu-bar app).

### Acceptance
- Add an executable target `TranslateTheDamnApp` to `Package.swift` (`.executableTarget(name: "TranslateTheDamnApp", dependencies: ["TranslateTheDamnCore"], path: "src/App")`). Platforms inherit macOS 14 from the package.
- Create `platforms/macos/src/App/AppDelegate.swift` with a `@main` entry (or a `main.swift`) that: creates `NSApplication.shared`, sets `activationPolicy = .accessory` (menu-bar app, NO Dock icon, NO main window — mirrors the Windows tray app), builds a minimal `NSMenu` main menu (the app-name menu with a Quit item ⌘Q, + a minimal Edit menu so text fields work later), assigns `app.delegate`, and runs `app.run()`.
- `swift build` succeeds (the App target compiles + links Core).
- `swift test` stays 22/22 green (no regression — the App target is separate from the test target).
- Do NOT hang: verify with `swift build` (and optionally `swift run TranslateTheDamnApp` behind a timeout that you kill — the app runs until Quit, so don't block on `swift run`). Building clean is the gate; launching is optional.

### Return
- The updated `platforms/macos/Package.swift` + new `platforms/macos/src/App/AppDelegate.swift`.
- EXACT `swift build` output (succeeds).
- EXACT `swift test` output (22/22 green).
- `git diff --stat`.

### Constraints
- Add ONLY `platforms/macos/src/App/` + edit `platforms/macos/Package.swift`.
- Do NOT modify Core, the conformance runner/tests, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, AppKit, Foundation. macOS 14+. Zero external deps.
- `setActivationPolicy(.accessory)` (no Dock icon, no main window). Do NOT enable App Sandbox.
- Run `swift build` + `swift test`; report real output. Do not claim pass unless build succeeds + 22 tests green.

---

## T-MAC-30

**Task-type**: code-impl  **Vendor**: kimi (default `kimi-code/kimi-for-coding`)  **Deps**: T-MAC-29 (App target)

### Goal
Implement the clipboard watcher (spec §4, §4.1) for macOS: poll `NSPasteboard.general.changeCount` on a ~250ms timer (macOS has NO clipboard change event), with the pipeline safety filters — self-write guard, skip non-text/empty/>maxChars, dedupe consecutive identical, debounce bursts, supersede. The pure filter logic goes in Core (unit-tested); the `NSPasteboard` polling + timer + wiring in the App target. NO conformance vector (UI/OS) — acceptance = unit tests for the filter logic + `swift build` green.

### Background (read; do not modify)
- spec §4 (dual-track triggering), §4.1 (pipeline filters/safety: self-write guard, skip rules, dedupe, debounce, supersede, last-translation cache).
- `platforms/macos/src/Core/TranslationPipeline.swift` (T-MAC-15) — the watcher feeds translations into it.
- `platforms/macos/src/App/AppDelegate.swift` (T-MAC-29) — where the watcher timer + `NSPasteboard` polling live.
- Windows reference: `platforms/windows/src/` ClipboardListener (self-write guard via hash) — read-only.

### Acceptance
- **Core** — new `platforms/macos/src/Core/ClipboardFilter.swift` with pure, injectable logic, unit-tested (`platforms/macos/tests/ClipboardFilterTests.swift`):
  - `shouldProcess(newText: String, lastProcessed: String?, maxChars: Int) -> Bool` — false if empty/whitespace, > maxChars, or duplicate of lastProcessed.
  - self-write guard: `markSelfWrite(text:)` + `isSelfWrite(text:) -> Bool` (hash the text; a change matching a self-written text is ignored).
  - debounce: a timestamp-based helper (ignore bursts within N ms) — testable with an injectable clock closure `() -> Date`.
- **App** — new `platforms/macos/src/App/ClipboardWatcher.swift`: polls `NSPasteboard.general.changeCount` on a ~250ms `Timer`; on change reads `string(forType: .string)`; runs it through `ClipboardFilter`; if it passes, invokes a callback `(String) -> Void` (→ pipeline). Honors a `listenClipboard` on/off toggle. Exposes `markSelfWrite(_:)` so the popup's copy button (later) can guard its own writes.
- Wire the watcher into `AppDelegate` (start on launch, gated by `ConfigService.defaultConfig().general.listenClipboard`).
- `swift build` succeeds; `swift test` = 22 + new ClipboardFilter tests green.

### Return
- New `ClipboardFilter.swift` (Core) + `ClipboardWatcher.swift` (App) + `ClipboardFilterTests.swift`; edited `AppDelegate.swift`.
- EXACT `swift build` + `swift test` output.
- `git diff --stat`.

### Constraints
- Add the new files + edit `AppDelegate.swift` only. Do NOT modify Core logic signatures, the conformance runner, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, AppKit, Foundation. The filter logic must be testable WITHOUT `NSPasteboard` (injectable clock + no AppKit in Core).
- Run `swift build` + `swift test`; report real output. Do not claim pass unless build + (22 + new) tests green.

---

## T-MAC-31

**Task-type**: code-impl  **Vendor**: opencode (model `tokenbox/deepseek-v4-pro`; pass `--sandbox danger-full-access`)  **Deps**: T-MAC-29 (App target)

### Goal
Implement the global hotkey (spec §4) via Carbon `RegisterEventHotKey` (preferred — NO TCC/accessibility permission prompt, unlike `NSEvent` global monitors). Configurable translate + toggle-listen hotkeys; registration failure surfaced as a conflict. Maps the Win32 VK codes (from `HotkeyParser`) to macOS Carbon keycodes. NO conformance vector (OS) — acceptance = unit tests for the VK→keycode map + `swift build` green.

### Background (read; do not modify)
- spec §4 (global hotkey — always active; translates current clipboard; configurable; conflict-checked).
- `platforms/macos/src/Core/HotkeyParser.swift` (T-MAC-13) — parses `"Ctrl+Alt+T"` → modifiers + **Win32 VK code** (T=84, F2=113, Space=32).
- `platforms/macos/CLAUDE.md` — prefer Carbon `RegisterEventHotKey` (no TCC).
- Windows reference: `platforms/windows/src/` HotkeyService (RegisterHotKey + conflict) — read-only.

### Acceptance
- **Core** — new `platforms/macos/src/Core/CarbonKeyMap.swift`, pure + unit-tested (`platforms/macos/tests/CarbonKeyMapTests.swift`):
  - `static func carbonKeyCode(fromVK vk: Int) -> UInt32?` — Win32 VK → macOS Carbon keycode (`kVK_*`): letters A–Z (VK 65–90 → `kVK_ANSI_A`…), F1–F24, Space (VK 32 → `kVK_Space`=49), digits, etc. Must return the correct keycode for the vector's VK codes (T=84, F2=113, Space=32) + common keys.
  - `static func carbonModifiers(hasControl: Bool, hasAlt: Bool, hasShift: Bool, hasWin: Bool) -> UInt32` — map to Carbon modifier flags: Win `Control`→`controlKey`, `Alt`→`optionKey`, `Shift`→`shiftKey`, `Win`→`cmdKey`.
- **App** — new `platforms/macos/src/App/HotkeyService.swift`: registers a global hotkey via Carbon `RegisterEventHotKey` (`import Carbon`). `register(hotkeyString: String, action: @escaping () -> Void) -> Bool` — parse via `HotkeyParser`, map VK→Carbon keycode + modifiers via `CarbonKeyMap`, `RegisterEventHotKey`; return `false` on failure (conflict/invalid). `unregister()`. Handle the translate hotkey + the toggle-listen hotkey (if non-empty). Install the Carbon event handler once (`InstallEventHandler` on `GetApplicationEventTarget` for `kEventClassKeyboard`/`kEventHotKeyPressed`).
- Wire into `AppDelegate`: register the configured hotkeys (from `ConfigService.defaultConfig().hotkey`) on launch; expose re-register on settings change.
- `swift build` succeeds (Carbon framework links); `swift test` = 22 + CarbonKeyMap tests green.

### Return
- New `CarbonKeyMap.swift` (Core) + `HotkeyService.swift` (App) + `CarbonKeyMapTests.swift`; edited `AppDelegate.swift`.
- EXACT `swift build` + `swift test` output.
- `git diff --stat`.

### Constraints
- Add the new files + edit `AppDelegate.swift` only. Do NOT modify Core logic signatures, the conformance runner, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Carbon `RegisterEventHotKey` (NOT `NSEvent` global monitor — that needs TCC). `import Carbon`.
- The VK→keycode map must be pure + unit-testable (no Carbon in Core). Carbon registration is App-layer.
- Run `swift build` + `swift test`; report real output. Do not claim pass unless build + (22 + new) tests green.

---

## T-MAC-32

**Task-type**: code-impl  **Vendor**: opencode (model `tokenbox/deepseek-v4-pro`; pass `--sandbox danger-full-access`)  **Deps**: T-MAC-29 (App target)

### Goal
Implement the non-focus-stealing translation popup (spec §8) for macOS: an `NSPanel` (`.nonactivatingPanel` + floating level, `hidesOnDeactivate=false`) with `NSVisualEffectView` vibrancy, showing source (muted) + translation (prominent) + 复制译文/关闭 buttons, hover-to-keep, auto-dismiss after `autoDismissSeconds`, scrollable, states 翻译中…→result→error. Strings from `strings/zh-CN.json`. NO conformance vector (UI) — acceptance = `swift build` green + spec-compliance (cross-reviewed).

### Background (read; do not modify)
- spec §8 (popup UX: no-focus-steal, vibrancy, source+translation+copy, top-center, hover-pause-dismiss, states loading→result→error).
- `strings/zh-CN.json` — popup strings (`popup.header.translating`=翻译中…, `popup.button.copy`=复制译文, `popup.button.copied`=已复制 ✓, `popup.button.close`=关闭, `popup.header.error`=翻译失败, `error.*`).
- `platforms/macos/CLAUDE.md` — NSPanel(nonactivatingPanel+floating) + NSVisualEffectView.
- `platforms/macos/src/App/AppDelegate.swift` (T-MAC-29) — where the popup is shown from.
- Windows reference: `platforms/windows/src/` PopupWindow (WS_EX_NOACTIVATE + acrylic + hover-keep + auto-dismiss) — read-only.

### Acceptance
- `TranslationPopup` (new `platforms/macos/src/App/TranslationPopup.swift`), an `NSPanel` subclass:
  - Style: `.nonactivatingPanel` style mask (+ `.titled`/`.fullSizeContentView`/`.borderless` as needed); `level = .floating`; `hidesOnDeactivate = false`; `isOpaque = false`; `backgroundColor = .clear`; `hasShadow = true`. Does NOT steal focus / activate the app.
  - Vibrancy: `NSVisualEffectView` (material `.hudWindow` or `.popover`; blending `.behindWindow`) as the content view.
  - Content: source text (muted, smaller) + translation text (prominent, larger) + 复制译文 button + 关闭 button. Scrollable (`NSScrollView` around the translation for long text). Dark scrim for legibility.
  - Position: top-center of the primary screen's visible frame.
  - Behavior: hover pauses the dismiss timer (`mouseEntered`/`mouseExited`); auto-dismiss after `autoDismissSeconds` (default 6) when not hovering; fade out.
  - States: `showLoading()` (翻译中…), `showResult(translation:source:)`, `showError(message:)` (status taxonomy → `error.*` strings).
  - Copy button: copies translation to `NSPasteboard` + (later) marks self-write via `ClipboardFilter.markSelfWrite` + shows 已复制 ✓ briefly. Close button: dismiss.
  - Methods: `show(source:translation:)` / `update(translation:)` / `dismiss()`.
- Strings from `strings/zh-CN.json` (load the catalog; don't hardcode Chinese).
- `swift build` succeeds; `swift test` green (no regression — popup is App-layer, not unit-tested, but build must pass).

### Return
- New `TranslationPopup.swift` (+ a strings loader if needed). EXACT `swift build` + `swift test` output. `git diff --stat`.

### Constraints
- Add new file(s) under `platforms/macos/src/App/`. Do NOT modify Core, the conformance runner, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, AppKit. Strings from `strings/zh-CN.json` (load, don't hardcode).
- NSPanel nonactivating + floating (NO focus steal). NSVisualEffectView vibrancy. No App Sandbox.
- Run `swift build` + `swift test`; report real output. Do not claim pass unless build + existing tests green (T-MAC-32).

---

## T-MAC-33

**Task-type**: code-impl  **Vendor**: kimi (default `kimi-code/kimi-for-coding`)  **Deps**: T-MAC-29 (App target)

### Goal
Implement the menu-bar tray (spec §3) for macOS: an `NSStatusItem` (menu-bar extra) with a tooltip (listening/paused) + menu (监听剪贴板 toggle / 打开设置… / 退出) + a persisted global on/off switch (when off, clipboard listening pauses). Strings from `strings/zh-CN.json`. NO conformance vector (UI) — acceptance = `swift build` green + spec-compliance.

### Background (read; do not modify)
- spec §3 (tray icon + global switch persisted), §4 (switch on/off gates clipboard listening).
- `strings/zh-CN.json` — tray strings (`tray.tooltip.listening`, `tray.tooltip.paused`, `tray.menu.listen`=监听剪贴板, `tray.menu.settings`=打开设置…, `tray.menu.exit`=退出).
- `platforms/macos/src/App/AppDelegate.swift` (T-MAC-29) — where the status item is created.
- Windows reference: `platforms/windows/src/` TrayIcon (NotifyIcon + switch) — read-only.

### Acceptance
- `TrayController` (new `platforms/macos/src/App/TrayController.swift`):
  - Creates an `NSStatusItem` (`statusBar.length = .square`) with a simple template glyph (NSImage — a small "文"/"T" glyph or SF Symbol `character`; `isTemplate = true` so it adapts to light/dark menu bar).
  - Tooltip: `tray.tooltip.listening` ("translate-the-damn(监听中)") when on, `tray.tooltip.paused` ("translate-the-damn(已暂停)") when off.
  - Menu: 监听剪贴板 (toggle, checkmark when on) / 打开设置… (callback to open settings) / 退出 (`NSApp.terminate`). From strings.
  - Global switch: `isListeningOn: Bool` — toggling persists to `config.general.listenClipboard` (via `ConfigService.save`) + starts/stops the `ClipboardWatcher`. When off, the watcher is stopped.
  - Methods: `setListening(_ on: Bool)`, menu `@objc` actions.
- Wire into `AppDelegate` (create the status item on launch; toggle callback → start/stop watcher + persist).
- Strings from `strings/zh-CN.json` (reuse the loader).
- `swift build` succeeds; `swift test` green (no regression).

### Return
- New `TrayController.swift`. EXACT `swift build` + `swift test` output. `git diff --stat`.

### Constraints
- Add new file(s) under `platforms/macos/src/App/`. Do NOT modify Core, the conformance runner, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, AppKit. Strings from `strings/zh-CN.json`. `NSStatusItem` (menu-bar extra; consistent with `.accessory` policy — no Dock icon).
- Run `swift build` + `swift test`; report real output. Do not claim pass unless build + existing tests green (T-MAC-33).

---

## T-MAC-34

**Task-type**: code-impl  **Vendor**: opencode (model `tokenbox/deepseek-v4-pro`; pass `--sandbox danger-full-access`)  **Deps**: T-MAC-29 (App target)

### Goal
Implement the SwiftUI settings window (spec §9) for macOS: grouped single page — 监听与触发 (listen toggle + hotkey capture w/ live conflict check), 翻译后端 (backend picker → editable model field from `modelCatalog` + per-backend fields incl. google/doubao apiKey/endpoint/target), 浮窗展示 (style acrylic/solid, autoDismiss slider, keep-on-hover), 通用 (start-at-login — stored as the shared `startWithWindows` key, wired to SMAppService in T-MAC-35). Writes `config.json` (via `ConfigService`) + hot-reloads the running pipeline. Strings from `strings/zh-CN.json`. NO conformance vector (UI) — acceptance = `swift build` green + spec-compliance.

### Background (read; do not modify)
- spec §9 (settings window: grouped single page; backend→model combobox; auth lamp; per-backend fields; hot-reload).
- `strings/zh-CN.json` — settings strings (`settings.title`, `settings.group.*`, `settings.field.*`, `settings.button.save/close`, `settings.status.saved`).
- `platforms/macos/src/Core/ConfigService.swift` (T-MAC-10) — load/save/defaultConfig.
- `platforms/macos/src/Core/HotkeyParser.swift` (T-MAC-13) + `platforms/macos/src/App/HotkeyService.swift` (T-MAC-31) — hotkey capture + conflict check (`register` fails on conflict).
- `platforms/macos/src/App/AppDelegate.swift` — settings window host.
- Windows reference: `platforms/windows/src/` SettingsWindow — read-only.

### Acceptance
- `SettingsWindow` (new `platforms/macos/src/App/SettingsWindow.swift`) — a SwiftUI view (or `NSWindow` hosting SwiftUI) with:
  - **监听与触发**: listen toggle + hotkey capture field with **live conflict check** (try `HotkeyService.register`; red/conflict indicator on failure).
  - **翻译后端**: backend picker → editable model field populated from `modelCatalog[backend]`; per-backend fields — cli backends: model/timeout (+ reasoning for codex, fallbackCommand for agy); http backends: apiKey/endpoint/target (+ source for google-v2 / targetLanguage for doubao).
  - **浮窗展示**: style (acrylic/solid), autoDismissSeconds slider, keepOnHover.
  - **通用**: start-at-login toggle (stored as `general.startWithWindows` — shared key, Law 4; SMAppService wiring in T-MAC-35).
  - Save button: `ConfigService.save` + hot-reload (notify AppDelegate → re-register hotkeys + start/stop watcher per `listenClipboard` + clear pipeline cache). Close button.
- Strings from `strings/zh-CN.json`.
- `swift build` succeeds; `swift test` green.

### Return
- New `SettingsWindow.swift`. EXACT `swift build` + `swift test` output. `git diff --stat`.

### Constraints
- Add new file(s) under `platforms/macos/src/App/`. Do NOT modify Core logic signatures, the conformance runner, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, SwiftUI + AppKit. Strings from `strings/zh-CN.json`.
- Keep the shared `startWithWindows` config key (Law 4); UI label may say 开机自启, but the stored key stays `startWithWindows` (SMAppService wiring in T-MAC-35).
- Run `swift build` + `swift test`; report real output. Do not claim pass unless build + existing tests green (T-MAC-34).

---

## T-MAC-35

**Task-type**: code-impl  **Vendor**: kimi (default `kimi-code/kimi-for-coding`)  **Deps**: T-MAC-29 (App target)

### Goal
Implement start-at-login (spec §3 — on macOS this is `SMAppService`) + the app icon (`.icns` via `iconutil`, single glyph source unified for tray + app). `SMAppService.mainApp.register()/unregister()` driven by the shared `general.startWithWindows` config flag. NO conformance vector (OS) — acceptance = `swift build` green + spec-compliance.

### Background (read; do not modify)
- spec §3 (start at login), §12 (app icon = tray glyph, single source).
- `platforms/macos/CLAUDE.md` — `SMAppService` (macOS 13+), `.icns` via `iconutil`.
- `platforms/macos/src/App/TrayController.swift` (T-MAC-33) — tray glyph (SF Symbol `character` / 文).
- `platforms/macos/src/Core/ConfigService.swift` — `general.startWithWindows` (shared key, Law 4).
- Windows reference: `platforms/windows/src/` — read-only.

### Acceptance
- `LoginService` (new `platforms/macos/src/App/LoginService.swift`): `setEnabled(_ on: Bool)` → `SMAppService.mainApp.register()` (on) / `unregister()` (off), with error handling (log on failure). `isEnabled() -> Bool` (query `SMAppService.mainApp.status`). Guard macOS 13+ availability (`if #available(macOS 13, *)`).
- App icon: a script `platforms/macos/scripts/build-icon.sh` that renders the single glyph ("文" / SF Symbol `character`) to PNGs at the standard iconset resolutions → `iconutil -c icns` → `app.icns`. (The `.icns` is bundled into the `.app` via `Info.plist` `CFBundleIconFile` in M4 / T-MAC-51; here just produce the `.icns` + the script.)
- Wire: AppDelegate applies `startWithWindows` on launch (`LoginService.setEnabled(config.general.startWithWindows)`) + on settings change. The settings window (T-MAC-34) start-at-login toggle calls `LoginService.setEnabled`.
- `swift build` succeeds; `swift test` green.

### Return
- New `LoginService.swift` + `scripts/build-icon.sh` (+ generated `app.icns` if the script runs). EXACT `swift build` + `swift test` output. `git diff --stat`.

### Constraints
- Add new file(s) under `platforms/macos/src/App/` (+ `platforms/macos/scripts/`). Do NOT modify Core, the conformance runner, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- `SMAppService` (macOS 13+); guard availability. The `startWithWindows` config key stays (Law 4) — `LoginService` maps it to `SMAppService`.
- Run `swift build` + `swift test`; report real output. Do not claim pass unless build + existing tests green (T-MAC-35).

---

## T-MAC-37

**Task-type**: code-impl  **Vendor**: opencode (model `tokenbox/deepseek-v4-pro`; pass `--sandbox danger-full-access`)  **Deps**: T-MAC-16 (PathResolver), T-MAC-14 (BackendManifest)

### Goal
Implement the REAL backend execution layer — the counterpart to M2's request-building. `ProcessRunner` (spawn CLI backends with double-timeout + kill-tree), `ProcessTranslator` (claude/codex/copilot/agy), `HttpTranslator` (google-v2/doubao), + `TranslatorRegistry` (backend id → translator). Conforms to the `Translator` protocol so `TranslationPipeline` actually translates (replaces the NoOpTranslator stub). Keep the protocol **SYNC** (the M2 pipeline-cache vector pins a sync fake translator); the pipeline runs off-main in T-MAC-36. NO conformance vector (execution/IO) — acceptance = unit tests for responsePath execution + `swift build` green; **pipeline-cache vector MUST stay green**.

### Background (read; do not modify)
- spec §6 (backends), §3.2 (reused patterns: double timeout, kill-tree, agy log diagnosis), §4.1 (supersede — deferred to T-MAC-36 async wiring).
- `platforms/macos/src/Core/BackendManifest.swift` + `HttpBackend.swift` (T-MAC-14) — `buildCall` + `responsePath` eval.
- `platforms/macos/src/Core/PathResolver.swift` (T-MAC-16), `AnsiStripper.swift` (T-MAC-12), `TranslationPipeline.swift` + `Translator` protocol (T-MAC-15).
- Windows reference: `platforms/windows/src/` ProcessTranslator/HttpTranslator/ProcessRunner — read-only.

### Acceptance
- `ProcessRunner` (new `platforms/macos/src/Core/ProcessRunner.swift`): spawn a `Process` (resolved via `PathResolver`) with args + env + stdin; capture stdout/stderr; **double timeout** (idle: kill on zero-output-for-N-sec = "stuck"; ceiling: hard cap) per spec §3.2; **kill-tree** on timeout (terminate process + children); return stdout (AnsiStripped) + exit code. Injectable clock/timers.
- `ProcessTranslator` (new `platforms/macos/src/Core/ProcessTranslator.swift`): conforms to `Translator`. For a CLI backend: read manifest def (args, promptVia, parse), resolve command via `PathResolver`, build args (placeholder subst), spawn via `ProcessRunner` (prompt via stdin/stdin-dash/arg per `promptVia`), `AnsiStripper` the output, parse (stdout-clean / jsonResultPath / jsonEvent per `parse` mode) → `TranslationResult`. Status taxonomy: Success/AuthFail/Timeout/NotFound/BadOutput/UnknownFail. agy fallback (`fallbackCommand` gemini) + log-file diagnosis (exit0+empty+auth-error-in-log).
- `HttpTranslator` (new `platforms/macos/src/Core/HttpTranslator.swift`): conforms to `Translator`. For an HTTP backend: `HttpBackend.buildCall` → `URLSession` (sync wrapper via semaphore — protocol is sync) → `responsePath` eval → `TranslationResult`. Status: Success/AuthFail/BadOutput.
- `TranslatorRegistry` (new `platforms/macos/src/Core/TranslatorRegistry.swift`): backend id → translator (claude/codex/copilot/agy → `ProcessTranslator`; google-v2/doubao → `HttpTranslator`). `translator(for backend: String, config: BackendConfig) -> Translator`.
- Keep the `Translator` protocol SYNC (`translate(text:model:) -> TranslationResult`) — do NOT change it (pipeline-cache vector pins a sync fake). `HttpTranslator` blocks on URLSession via semaphore (pipeline runs off-main in T-MAC-36).
- Unit tests for `responsePath` execution (eval against sample CLI/HTTP responses) + status mapping. `swift build` green; `swift test` green (existing 71 + new). **pipeline-cache vector MUST stay green**.
- Do NOT wire into AppDelegate yet (that's T-MAC-36); build the execution layer + registry + tests only.

### Return
- New `ProcessRunner.swift`, `ProcessTranslator.swift`, `HttpTranslator.swift`, `TranslatorRegistry.swift` (+ tests). EXACT `swift build` + `swift test` output (pipeline-cache green). `git diff --stat`.

### Constraints
- Add new Core files + tests. Do NOT modify the conformance runner, existing Core logic signatures, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`. (Tests go under `platforms/macos/tests/`.)
- Native Swift, Foundation (`Process`, `URLSession`). Injectable timers/clock for testability. Keep `Translator` protocol sync.
- Run `swift build` + `swift test`; report real output. Do not claim pass unless build + (71 + new) tests green AND pipeline-cache vector still green (T-MAC-37).

---

## T-MAC-36

**Task-type**: code-impl  **Vendor**: opencode (model `tokenbox/deepseek-v4-pro`; pass `--sandbox danger-full-access`)  **Deps**: T-MAC-30, T-MAC-31, T-MAC-32, T-MAC-33, T-MAC-34, T-MAC-35, T-MAC-37

### Goal
The **app composition root** — wire everything into a working app: `ConfigService` → `TranslationPipeline` (with the real `TranslatorRegistry` from T-MAC-37) → `ClipboardWatcher` + `HotkeyService` → `TranslationPopup` + `TrayController` + `SettingsWindow`. Run the pipeline **off-main** (so the UI doesn't block) + implement **supersede** (a new trigger cancels an in-flight translation). Replace the `NoOpTranslator` stub with the real registry. After this the app ACTUALLY translates end-to-end. NO conformance vector (integration) — acceptance = `swift build` green + `swift test` green (pipeline-cache vector still green) + wiring correct (cross-reviewed; deep adversarial → T-MAC-40).

### Background (read; do not modify)
- spec §3 (architecture: ConfigService→Pipeline→(Clipboard|Hotkey)→Popup+Tray+Settings), §4.1 (supersede), §3.2 (neutral sandbox CWD for CLI spawn).
- M3 components: `ClipboardWatcher` (T-MAC-30), `HotkeyService` (T-MAC-31), `TranslationPopup` (T-MAC-32), `TrayController` (T-MAC-33), `SettingsWindow` (T-MAC-34), `LoginService` (T-MAC-35).
- T-MAC-37: `ProcessRunner`/`ProcessTranslator`/`HttpTranslator`/`TranslatorRegistry`.
- `platforms/macos/src/App/AppDelegate.swift` — the composition root (currently has the `NoOpTranslator` stub).

### Acceptance
- `AppDelegate` (the `@main` root) wires:
  - Load config (`ConfigService.load` or `defaultConfig`).
  - Build `TranslatorRegistry` (T-MAC-37) + `TranslationPipeline` with the real translator for `config.general.activeBackend`.
  - `ClipboardWatcher`: on a change passing `ClipboardFilter` → translate via pipeline (off-main) → popup (`showLoading` → `update` result / `showError`).
  - `HotkeyService`: translate hotkey → translate current clipboard (off-main) → popup; toggle-listen hotkey → `tray.setListening`.
  - `TrayController`: toggle → start/stop watcher + persist; settings → open `SettingsWindow`; exit → terminate.
  - `SettingsWindow` save → `hotReload` (re-register hotkeys, start/stop watcher, recreate pipeline with new backend clearing cache, `LoginService.setEnabled`).
  - `LoginService`: apply `startWithWindows` on launch.
- **Off-main pipeline + supersede**: run translations on a background queue (`DispatchQueue.global` or a `Task`); a new trigger cancels the in-flight translation (cancel the `Task` / supersede flag) per spec §4.1. Popup shows 翻译中… immediately, then updates with the result.
- **Neutral sandbox CWD**: spawn CLI backends from an empty/neutral CWD (so they don't load the current project's context) per spec §3.2 (ensure `ProcessRunner`/composition sets it).
- Replace the `NoOpTranslator` stub with the real `TranslatorRegistry`.
- `swift build` green; `swift test` green (pipeline-cache vector still green — don't break it).

### Return
- Edited `AppDelegate.swift` (composition) + any minimal glue. EXACT `swift build` + `swift test` output. `git diff --stat`.

### Constraints
- Edit `AppDelegate` (+ minimal glue). Do NOT modify Core logic signatures, the conformance runner, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift, AppKit/Foundation. Off-main pipeline + supersede. Neutral sandbox CWD for CLI spawn.
- Run `swift build` + `swift test`; report real output. Do not claim pass unless build + existing tests green AND pipeline-cache vector green (T-MAC-36).

---

## T-MAC-40

**Task-type**: code-review-adversarial  **Vendor**: mimo (model `xiaomi/mimo-v2.5-pro`, `--reasoning xhigh` → `--variant max`; read-only sandbox)  **Deps**: T-MAC-30, T-MAC-31, T-MAC-32, T-MAC-33, T-MAC-34, T-MAC-35, T-MAC-36, T-MAC-37

### Goal
Adversarial cross-review of the **M3 native layer** (all `platforms/macos/src/App/*.swift` + the M3 Core additions) against spec §3-9 + PORTING-macos. You are a DIFFERENT channel than the builders (kimi + opencode) — find what they missed. **Output the FULL review (verdict + findings) AS YOUR FINAL MESSAGE TEXT** — do NOT write to a file (read-only sandbox can't), do NOT ask "shall I proceed?", just output the complete review text so hopper captures it into the output.md. Do NOT edit code.

### Background (read; do not modify any code)
- All M3 App files: `AppDelegate`, `ClipboardWatcher`, `HotkeyService`, `TranslationPopup`, `TrayController`, `SettingsWindow`, `LoginService` + M3 Core additions (`ClipboardFilter`, `CarbonKeyMap`, `ProcessRunner`, `ProcessTranslator`, `HttpTranslator`, `TranslatorRegistry`).
- spec §3-9 (architecture, triggering, popup UX, settings), §4.1 (pipeline safety), `docs/PORTING-macos.md`.
- `conformance/` (the vectors — must still pass).
- Windows reference: `platforms/windows/src/`.
- `CONSTITUTION.md` (Laws).

### Acceptance (review output AS TEXT — verdict + findings)
- **Verdict**: PASS / PASS_WITH_CHANGES / REWORK.
- **Findings** (P0/P1/P2, file:line, issue, fix). Focus:
  1. No-focus-steal correctness (popup `canBecomeKey/Main=false`, `nonactivatingPanel`).
  2. Carbon hotkey no-TCC (`RegisterEventHotKey`, NOT `NSEvent` global monitor).
  3. Self-write guard (clipboard loop prevention).
  4. Vibrancy + popup states + hover-keep + auto-dismiss + scroll.
  5. PATH resolution (GUI PATH gotcha — `knownInstallPaths` + login-shell; the F4 deadlock fix held).
  6. Strings parity (`strings/zh-CN.json`; the missing `settings.field.source`).
  7. `ProcessRunner` double-timeout + kill-tree + deadlock-free.
  8. Supersede correctness (cancel in-flight translation).
  9. Neutral sandbox CWD for CLI spawn (spec §3.2).
  10. Law 6 (real translators read `spec/backends.json`, not hardcode).
- **CRITICAL**: output the FULL review as your final message text (hopper captures it into `output.md`). Do NOT write a file. Do NOT ask "shall I proceed?". Read-only sandbox is correct for a review task.

### Return
The review (verdict + findings) as your final message text.

### Constraints
- Review-only. No code edits. Read-only sandbox correct. Output the review AS TEXT (don't write a file; don't ask to proceed).

---

## T-MAC-40F

**Task-type**: code-impl  **Vendor**: opencode (model `tokenbox/deepseek-v4-pro`; pass `--sandbox danger-full-access`)  **Deps**: T-MAC-40 (M3 review done)

### Goal
Fix the must-fix findings from the T-MAC-40 subagent adversarial review of M3. After your change, `swift test` must STILL be **116/116 green** (pipeline-cache + all vectors) — do not break anything. These are correctness/parity fixes.

### Fixes (exact)

**P0-1 — CLI translations run with empty prompt template** (`TranslatorRegistry.swift:23` + `AppDelegate.buildPipeline` ~`AppDelegate.swift:170-177`): `TranslatorRegistry.translator(for:config:)` constructs `ProcessTranslator` with `promptTemplate: ""` (default, never supplied) → the LLM gets raw text with NO translation instructions. Fix: thread `promptTemplate` through — `translator(for:config:promptTemplate:)` reads `config.translation.promptTemplate`; `AppDelegate.buildPipeline` passes it. Match Windows `TranslatorRegistry.Build` (passes `cfg.Translation.PromptTemplate`). Spec §5 contract.

**P0-2 — agy `fallbackCommand` (gemini fallback) never invoked** (`ProcessTranslator.swift:18-75`): `translate` runs only the primary command; never reads `fallbackCommand`/`fallbackArgs`. So agy's gemini fallback (spec §6, manifest `agy.fallbackCommand: "gemini"`) is unimplemented. Fix: port the fallback branch — after `classifyFailure`, if status is `.notFound` or `.badOutput` AND a fallback resolves (manifest `fallbackCommand` + `fallbackArgs`), run it via `ProcessRunner` and return its result on success (prefer fallback on NotFound, original on BadOutput — match Windows `ManifestCliBackend.TranslateAsync`).

**P1-1 — Supersede is dead code; in-flight never cancelled** (`AppDelegate.swift:17,106-144` + `ProcessRunner.run`): `translationQueue` is serial (queues behind, no preempt) + no cancellation through the pipeline. Fix: add a cancellation hook to `ProcessRunner.run` (a `shouldCancel: () -> Bool` closure checked in the 50ms poll loop; if true → `killTree` + return a cancelled result). In AppDelegate, when a new `translate()` arrives, cancel the in-flight (kill the previous process). At minimum, kill the previous process when a new trigger arrives. Keep the UUID `isCurrent` guard (discard stale results).

**P1-2 — `ProcessRunner` idle timeout inert** (`ProcessTranslator.swift:48` passes `idleMs: 0`): idle-kill never runs; a stuck CLI runs the full ceiling. Fix: pass a non-zero `idleMs` (e.g. 10-15s) from `ProcessTranslator` (spec §3.2 double-timeout: idle = "stuck on zero output" + ceiling = hard cap). Configurable, default sensible non-zero.

**P2-2 — `HttpTranslator` force-unwraps URL** (`HttpTranslator.swift:63`): `URL(string: call.url)!` crashes on a malformed endpoint. Fix: `guard let url = URL(string: call.url) else { return .failed(.unknownFail, "malformed endpoint") }`. (Optionally honor `config.timeoutSec` instead of hardcoded 60s — do if easy.)

**P2-4 — Popup `NSScreen.main` unreliable for accessory app** (`TranslationPopup.swift:333`): with `.accessory` + `canBecomeKey=false`, `NSScreen.main` returns another app's screen. Fix: use `NSScreen.screens.first` (menu-bar/primary screen) for positioning (spec §8 "primary monitor's work area").

### NOT in scope (defer to M4 polish)
- P2-1 (`wantsLogFile` field heuristic), P2-3 (missing strings keys — add `settings.field.source` etc. to `strings/zh-CN.json` in M4), P2-5 (`markSelfWrite` hash→exact-string), P2-6 (`StringsLoader` fallback drift).

### Return
- The edited files (`TranslatorRegistry`, `ProcessTranslator`, `ProcessRunner`, `AppDelegate`, `HttpTranslator`, `TranslationPopup`). EXACT `swift test` output (116/116 green). `git diff --stat`.

### Constraints
- Edit ONLY the listed files under `platforms/macos/`. Do NOT modify the conformance runner, `/spec`, `/conformance`, `CONSTITUTION.md`, or `platforms/windows/`.
- Native Swift. Run `swift test`; report real output. Do not claim pass unless 116/116 green (T-MAC-40F).

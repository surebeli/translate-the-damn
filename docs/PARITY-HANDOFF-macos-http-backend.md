# macOS handoff — generic HTTP backend (`{prompt}`) + custom provider + protocol select

**Why:** Windows landed `openai-http` / `anthropic-http` (spec/backends.json) + the `{prompt}` body var +
the custom-provider protocol fallback. The shared vector `conformance/backend-requests.json` gained two
cases (`openai-http /chat/completions`, `anthropic-http /messages`). **These run on the macOS `swift test`
runner too and are RED until the changes below land** — that is the Law-2 forcing function, intended.

**Windows reference commit:** ManifestHttpBackend `{prompt}` plumbing + TranslatorRegistry protocol
fallback + BackendConfig.Protocol + portable ASCII-only vector cases. Verified live end-to-end
(deepseek-http 2.3s, mimo-http 3.3s, kimi-http /messages 2.4s).

## Exact macOS changes (mirror Windows; no `switch(id)`)

1. **`platforms/macos/src/Core/HttpBackend.swift`**
   - `buildCall` gains a `promptTemplate: String = ""` parameter; inside, compute
     `let prompt = PromptBuilder.build(promptTemplate, content: text)` and expose `"prompt"` in the
     substitution vars map (alongside `text`/`apiKey`/`model`/…). This is the macOS twin of
     `ManifestHttpBackend.Vars()["prompt"]`.
   - **Endpoint fix (audit P1):** `buildCall` currently reads `def["endpoint"]` and ignores
     `config.endpoint` (HttpBackend.swift:79). Change to prefer `config.endpoint` when non-empty
     (mirror `ManifestHttpBackend.Endpoint`, ManifestHttpBackend.cs:25) — without this, custom providers
     all hit the empty manifest endpoint.
   - Thread `promptTemplate` from `HttpTranslator.init` → `buildCall`.

2. **`platforms/macos/src/Core/TranslatorRegistry.swift`**
   - Pass the prompt template into the HTTP translator (as the CLI path already does).
   - **Custom-provider fallback:** when an id is absent from the manifest, resolve a def by
     `config.protocol` (`"openai"` → `openai-http`, `"anthropic"` → `anthropic-http`); else skip.
     (Twin of TranslatorRegistry.cs.)

3. **`platforms/macos/src/Core/AppConfig.swift` `BackendConfig`** — add `var protocol: String?`
   (Codable, optional; **no config-version bump**, Law 4). Mirror into the Swift `BackendTestConfig`
   (HttpBackend.swift:23-52) so the conformance runner can read `protocol` from a case.

4. **`platforms/macos/.../BackendRequestsTests.swift`** — thread a `promptTemplate` field from each case
   into `buildCall` (the Windows runner reads `c["promptTemplate"]`). The two new cases assert
   **ASCII-only** body substrings (`"role":"user"`, `"stream":false`, `"max_tokens":4096`, `Hello`,
   `Translate to zh`) — do NOT assert raw CJK: C# escapes CJK as `\uXXXX`, Swift `JSONSerialization`
   emits raw UTF-8, so a raw-CJK assert is non-portable (audit P0-2). If you later want a CJK assert,
   first normalize one encoder.

5. **Verify:** `swift test` green (the two new `backend-requests` cases pass), then flip
   `PARITY.md` rows "openai-http / anthropic-http" and "Custom provider" macOS ⬜ → ✅/🚧.

## Also landed on Windows — macOS must mirror (these now make macOS CI RED until done)

- **Unified target language** (`config-defaults` vector now asserts `translation.promptTemplate` contains `{target}`
  AND `translation.targetLanguage` == "简体中文"). macOS needs: a `TargetLanguage` field on Swift `TranslationConfig`
  (default "简体中文"); the default prompt template uses `{target}` (replace the hardcoded 简体中文); `PromptBuilder.withTarget(template, target)`
  resolving `{target}` once in `TranslatorRegistry` before `{content}`; auto-upgrade of the old (pre-`{target}`) default on load.
  A global "目标语言" picker in macOS settings. → both `config-defaults` and `prompt-builder` go green.
- **Custom-provider add/delete + protocol radio** UI (Win ✅): macOS settings needs an add-provider flow + protocol picker
  + dynamic backend enumeration (don't hardcode the list).
- **Live `/models` enumeration for API backends** (Win): derive `…/chat/completions`|`…/messages` → `…/models`, GET with
  the protocol auth header, parse OpenAI-shaped `data[].id`.

- **`chatPath` endpoint normalization** (Win): the openai-http/anthropic-http manifest entries gained `chatPath`
  (`/chat/completions`, `/messages`); `ManifestHttpBackend.Endpoint` appends it when the configured endpoint is a
  BASE (e.g. `…/v1`) — matching the `@ai-sdk/openai-compatible` convention. Mirror in Swift `HttpBackend`. A new
  `backend-requests` case (base endpoint → normalized URL) is RED on macOS until done.
- **Robust `/models` enumeration** (Win): multi-candidate paths (`/v1/models` first for a version-less base) + multi-shape
  parse (OpenAI `data[].id`, Ollama `models[].name`, bare arrays) + model-dropdown-open fetch from unsaved fields.
- **Credential auto-discovery** (Phase 2, Win ✅): `CredentialClassifier` (static-key/OAuth boundary) + `CredentialDiscovery.Scan`
  (env + opencode + codex; cc-switch SQLite deferred). The shared vector `conformance/credential-discovery.json` (9 cases incl.
  OAuth-SKIP) now runs on macOS CI too → **RED until** macOS ports the classifier (same host map + OAuth skip rules) and a
  scanner + a 检测已有密钥 UI. Owner decisions: plaintext + masking + consent.

## Not in scope here
- (nothing — all Phase-1/2 Windows features are listed above for the macOS mirror).

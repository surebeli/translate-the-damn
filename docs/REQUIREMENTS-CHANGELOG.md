# Requirements changelog

Living record of requirement **changes** and **additions** (per the owner's "及时记录"). Newest first.
Implementation status is tracked in `PARITY.md` + the task list; this file captures *intent/decisions*.

## 2026-06-22

### Changes (变更)
- **Default translate hotkey is per-platform.** Was a single shared default `Ctrl+Alt+T` (pinned by
  the `config-defaults` vector). Now each platform owns its default; the assertion was **un-pinned**
  from the shared vector and each platform verifies with a local test. **Windows = `Shift+Alt+C`**;
  macOS picks its own (tracked). (spec §7; PARITY row "Default translate hotkey".)
- **Backend invocation fixes (CLI):**
  - **codex** — `ProcessRunner` now sets `StandardInputEncoding = UTF-8` when piping; fixes
    "stdin needs utf-8" on zh-CN Windows for Chinese prompts. (Windows-specific.)
  - **copilot** — manifest corrected to the real non-interactive form `-p <prompt> --model <m>
    --allow-all-tools` (dropped dead `-s`/`--no-ask-user`; `--allow-all-tools` is required); default
    model `claude-haiku-4.5` → **`auto`**; catalog → `auto/gpt-5.2/gpt-5-mini/claude-sonnet-4.5`.
    Root cause of "model … from --model flag is not available" = invalid model name + stale flags.
  - **modelCatalog refresh-on-load** — the built-in model catalog is now refreshed from defaults on
    every config load (it is built-in data, not user state), so model-list fixes reach existing
    configs. The user's chosen model is preserved.
  - **agy** — added `--dangerously-skip-permissions` (correct non-interactive flag). **Diagnosed as
    upstream-blocked**, NOT an app bug: agy `-p` exits but writes nothing to stdout (#27466, confirmed
    locally), AND the `gemini` fallback returns `IneligibleTierError` (Google retired the gemini-cli
    free tier → "migrate to Antigravity"). Recommended other backends. **Re-research pending.**

### Additions (新增)
- **Generic HTTP LLM backend + custom provider + credential auto-discovery** — *Phase 1 LANDED + live-verified (Win); Phase 2 (auto-discovery) pending*.
  Driven by owner latency tests: same Kimi model is **1.8–3.6 s over HTTP `/messages` vs 4.7–6.7 s via the kimi-code CLI**
  (HTTP ~halves it); fast models hit 1–2.5 s (deepseek 1.2–3.2 s, mimo-v2.5 2.4–2.9 s, doubao 1.1 s). Decision: **add HTTP for the
  static-key long tail, keep the subscription CLIs** (claude/codex/copilot/agy ride flat-rate OAuth; reuse is ToS-banned). New asks
  folded in: **(R2) custom provider** (user types baseURL+key) and **(R3) protocol select OpenAI `/chat/completions` vs Anthropic
  `/messages`**. Two generic manifest entries (`openai-http`, `anthropic-http`) cover the whole long tail as Law-6 data (no `switch(id)`);
  the existing `ManifestHttpBackend` interprets them after a one-line `{prompt}` var addition. **Key discovery:** Kimi Code
  (`api.kimi.com/coding`) returns `access_terminated` to OpenAI `/chat/completions` (coding-agent allow-list) but works over Anthropic
  `/messages` with the same `sk-kimi` key. **(R4) auto-discovery:** the owner machine already holds reusable STATIC keys (cc-switch DB,
  opencode `auth.json`, codex `config.toml`) for DeepSeek/MiMo/Kimi/tokenbox — so "用过即免配置" is feasible. **(R5) security:**
  static keys only; **never scrape OAuth tokens** (`~/.claude`, `~/.gemini`, copilot, codex-oauth); explicit consent; OS secret store;
  masking. Full plan: `docs/superpowers/specs/2026-06-22-http-backend-custom-provider-autodiscovery.md`.
  **Audit (6-agent, vs real code): GO-WITH-FIXES** — the `{prompt}` change is NOT one line (ctor+field+registry+test-layer+macOS);
  cross-platform JSON-escape divergence (C# `\uXXXX` vs Swift raw UTF-8 → vectors assert ASCII-only); custom ids get dropped if not in
  the manifest (added a protocol→template registry fallback); R5 secret store doesn't exist (config plaintext today). Owner decisions:
  **plaintext + masking + consent** storage; **defer cc-switch SQLite** (v1 = env + opencode + codex). **Phase 1 LANDED (Win):**
  `openai-http`/`anthropic-http` + `{prompt}` plumbing + `BackendConfig.Protocol` + registry fallback; `backend-requests` +2 portable cases
  GREEN (287/0); live end-to-end on real keys — deepseek-http **2.3 s**, mimo-http **3.3 s**, kimi-http (Anthropic `/messages`) **2.4 s**.
  PARITY: HTTP backends Win ✅, custom-provider Win 🚧, auto-discovery ⬜. macOS mirror: `docs/PARITY-HANDOFF-macos-http-backend.md`
  (2 shared cases RED on macOS CI until it lands — Law-2 forcing function).
  **Phase 1 FINISHED (Win, 298/0):** (1) **custom-provider add/delete dialog** + **OpenAI/Anthropic protocol radio** (registry resolves
  custom ids by protocol, no `switch(id)`); (2) **unified target language** — `{target}` is now a prompt variable resolved once in the
  registry from `translation.targetLanguage`, applied across ALL prompt-driven backends (CLI + openai/anthropic-http); old default template
  auto-upgrades on load; global 目标语言 picker; `config-defaults`/`prompt-builder` vectors updated; (3) **live `/models` enumeration** for API
  backends (derive `/models` from the chat endpoint, GET, parse `data[].id` — verified deepseek/mimo/kimi); (4) dropdown polish — `CLI`/`API`
  tags, `-http` suffix stripped, ordered doubao→google→other-API→CLI→暂不支持; per-backend Target field hidden for generic API (it's google/doubao-only;
  `targetLanguageDefault` was dead config). Speed finding: a thinking/effort knob gives **negligible** latency benefit (measured mimo no-change,
  kimi ~0.3s noise) — the doubao/google gap is structural (NMT vs general LLM), so not added. PARITY: custom-provider + target-language Win ✅.
  **Phase 2 LANDED (Win, 325/0): credential auto-discovery.** `CredentialClassifier` (pure, conformance-pinned static-key/OAuth
  boundary) + `CredentialDiscovery.Scan` reads **env vars + opencode (`auth.json`/`opencode.json`) + codex (`config.toml`)** —
  **cc-switch SQLite deferred** per decision. Hard-skips OAuth (JWT/`ya29.`/`1//`/`gho_`/long tokens) + subscription hosts
  (anthropic.com/claude.ai/googleapis/githubcopilot). Host→provider/protocol map (deepseek/mimo/moonshot/kimi→anthropic/tokbox/
  openrouter/openai + generic). UI: **🔍 检测已有密钥** button → consent checklist (provider · protocol · masked · provenance) →
  import as http backends. **Plaintext + masking + consent** per decision. Vector `credential-discovery.json` (9 cases incl.
  OAuth-SKIP) green; verified live on the owner machine — found DeepSeek + MiMo-Token-Plan + tokenbox (masked), OAuth stores skipped.
  Also: **tokbox/relay support** — OpenAI-compatible (not Anthropic; probe-confirmed); added `chatPath` endpoint normalization so a
  `/v1` base auto-appends `/chat/completions` (matches `@ai-sdk/openai-compatible`); robust `/models` enumeration (multi-candidate
  path + multi-shape parse: OpenAI `data[].id` / Ollama `models[].name` / bare arrays); model-dropdown-open fetch using unsaved fields.
  PARITY: auto-discovery Win ✅. **Remaining:** macOS mirror (`docs/PARITY-HANDOFF-macos-http-backend.md`) — HTTP `{prompt}` +
  custom provider + target language + `/models` + chatPath + credential-discovery vector all pending there (Law-2 forcing function).
- **Per-vendor effort-tier selector + backend doctor** (spec §6/§9) — *implemented*. Manifest-driven
  (`effortTiers`, conditional `argsAppend`, `probe`); editable effort ComboBox; 诊断 button + live auth
  lamp + 深度检测 (local-default, opt-in live `-p`). Vectors: `effort-tiers`, `doctor-probe`,
  `doctor-classify`. Windows 🚧 (walkthrough pending), macOS handoff (`docs/PARITY-HANDOFF-macos-effort-doctor.md`).
- **New CLI vendors: kimi-code, mimo, opencode** — *implemented (spec-first; 258 vectors green)*. Added
  to manifest + DefaultConfig (6→9 backends) + conformance (`effort-tiers`/`doctor-probe`/`doctor-classify`
  + argv). opencode verified live ($0). Required two new generic interpreter capabilities (Law-6, no
  switch(id)): a **JSONL/stream-json extractor** (`parse.jsonl` + `jsonlType`/`jsonlTextPath`; opencode &
  kimi & mimo) and a **fail-wins probe mode** (`probe.failWins`; opencode "credentials" ⊂ "0 credentials").
  `EnsureDefaults` now **merges** new default backends into existing configs (TryAdd) so they appear
  without wiping user settings. **Owner-test refinements (2026-06-22, after live testing):**
  - **Backend dropdown hints** — items now show a status suffix: `agy — 暂不支持`, `google-v2 — API 接入`,
    `doubao — API 接入` (ComboBoxItem Content+Tag; raw id preserved for lookup).
  - **mimo output** — text mode leaked a `> build · <model>` chrome header; switched mimo to
    **`--format json`** + the JSONL extractor (answer = `type==text` → `part.text`, same as opencode).
    Structure verified live; final UTF-8 bytes pending the owner's in-app test (offline PowerShell capture
    re-encodes pipes / mimo suppresses stdout to a non-TTY file).
  - **Live model enumeration** — opencode shipped only 6 of 21 local models (pruned snapshot). Added
    generic `modelsCmd` (`["models"]`) + `ModelEnumerator`; the settings model dropdown now refreshes
    **live** from `<cli> models` (opencode/mimo), falling back to the static catalog. (`ParseModels` unit-tested.)
- **agy re-research** — web-search a working workaround (newer version / flag / output mode) for the
  `-p` no-stdout + gemini-tier issue; integrate if viable, else document as upstream-blocked.
  **DECIDED (owner, B):** root cause confirmed = upstream antigravity-cli **#76** (`-p` suppresses
  stdout when non-TTY; 1.0.10 is newest, no flag fixes it). A winpty PTY wrapper *would* fix it (option
  A), but the owner chose **B: leave agy `best-effort`/degraded and rely on the three new vendors**.
  No winpty wrapper wired. (Research: `.hopper/RESEARCH-new-vendors-2026-06-22.md`.)
- **New vendors decision:** add **opencode** (high-confidence, verified live $0), **kimi** (high),
  **mimo** (medium / `best-effort`). All `run`/`-p` non-interactive, neutral-CWD, ANSI-stripped;
  opencode/kimi emit JSONL/stream-json → a generic JSONL extractor is added to the interpreter;
  opencode's auth probe is **fail-wins** ("credentials" ⊂ "0 credentials"). backends 6→9.

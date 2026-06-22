# Design — Generic HTTP LLM backend + custom provider + credential auto-discovery

**Status:** DRAFT (executable) · **Date:** 2026-06-22 · **Owner gate:** audit → land
**Source research:** `.hopper/RESEARCH-meta-cli-vs-vendor-2026-06-22.md` + workflow `wf_7c204181-929`
(9-agent swarm: this-machine probe + Win/mac/Linux cred catalogs + endpoints + security/UX, adversarially verified).

## Why (measured, owner machine, short zh-CN sentence)

| Path | Latency | |
|---|---|---|
| kimi-for-coding — **CLI** | 4.7–6.7 s | (mimo CLI: hung >10 min) |
| kimi-for-coding — **HTTP `/messages`** (same model) | **1.8–3.6 s** | HTTP ~halves it |
| mimo-v2.5 — HTTP | 2.4–2.9 s | |
| deepseek-v4-flash — HTTP | 1.2–3.2 s | |
| doubao / google-NMT — HTTP | 1.1 s / 0.44 s | already HTTP |

Same model, HTTP roughly halves wall-clock (removes CLI cold-start + agent runtime). Fast models land 1–2.5 s.
For a hotkey/clipboard translator, sub-2.5 s vs 5–7 s is "instant vs waiting". **HTTP is necessary** for the
static-key long tail. It does **not** replace the subscription CLIs (claude/codex/copilot/agy ride flat-rate
OAuth at $0/margin; that auth can't ride generic HTTP and reuse is ToS-banned). **Add HTTP, keep the CLIs.**

## Requirements (incl. the 2 new owner asks)

- R1 Generic HTTP LLM backend, manifest-driven (Law 6), interpreted by the existing `ManifestHttpBackend` — no `switch(id)`.
- R2 **Custom provider**: user adds a backend by typing baseURL + key (+ model).  ← new ask #1
- R3 **Protocol select**: per provider, choose **OpenAI** (`/chat/completions`) or **Anthropic** (`/messages`).  ← new ask #2
- R4 Credential **auto-discovery**: detect already-configured static keys on the machine so the user needn't re-enter (manual only when nothing found).
- R5 Security: static keys only; never scrape OAuth subscription tokens; explicit consent; OS secret store; masking.

## Migration map (additive — same MAJOR.MINOR, more backends; no removals)

| Vendor | Disposition | Protocol | Note |
|---|---|---|---|
| DeepSeek | **→ HTTP** | OpenAI `/chat/completions` @ `api.deepseek.com` | static key, 1.2–3.2 s |
| Xiaomi MiMo (PAYG) | **→ HTTP** | OpenAI @ `api.xiaomimimo.com/v1` | static key, 2.4–2.9 s |
| MiMo Token-Plan CN | **→ HTTP** | OpenAI @ `token-plan-cn.xiaomimimo.com/v1` | **distinct base + key** |
| Moonshot (general) | **→ HTTP** | OpenAI @ `api.moonshot.ai/v1` | static key |
| **Kimi Code** | **→ HTTP** | **Anthropic `/messages`** @ `api.kimi.com/coding` | OpenAI path returns `access_terminated`; **must** use `/messages` |
| tokenbox/Homelander (relay) | optional HTTP | OpenAI @ `tokbox-api.netease.im/v1` | discovered on machine |
| google-v2, doubao | **stay HTTP** | own REST shapes | unchanged |
| claude, codex, copilot, agy | **stay CLI** | — | subscription OAuth; cannot migrate (ToS) |
| opencode, kimi, mimo (CLI) | **keep** | — | additive; HTTP ids are new, not replacements |

## Protocol shapes — TWO generic manifest entries (Law-6 data, no code branch)

`{prompt}` = `PromptBuilder.Build(translation rules, source text)`; `{model}`/`{apiKey}`/endpoint all from config.json.

**A. `openai-http`** — `POST {endpoint}` (`…/chat/completions`)
headers `Authorization: Bearer {apiKey}`, `Content-Type: application/json`
body `{ "model":"{model}", "messages":[{"role":"user","content":"{prompt}"}], "stream":false }`
`responsePath: "choices[0].message.content"`  (DeepSeek/MiMo/Moonshot/tokenbox)

**B. `anthropic-http`** — `POST {endpoint}` (`…/v1/messages`)
headers `x-api-key: {apiKey}`, `anthropic-version: 2023-06-01`, `Content-Type: application/json`
body `{ "model":"{model}", "max_tokens":4096, "messages":[{"role":"user","content":"{prompt}"}] }`
`responsePath: "content[type=text].text"`  (Kimi Code mandatory; any Claude-compatible)

Both `responsePath` forms already work via `ManifestEngine.Eval` (array index + `arr[key=value]`, as doubao/google use).
**Custom provider (R2/R3)** = a config.json backend of `type:http` whose `endpoint`/`model`/`apiKey` are user-typed and
whose **protocol radio** selects template A or B. No per-vendor entry required.

## Auto-discovery (R4) — read-only, static-key only, consent-gated

Confirmed present on the owner machine (keys redacted): **cc-switch DB** `~/.cc-switch/cc-switch.db`
(`providers` table → static `ANTHROPIC_BASE_URL`+`ANTHROPIC_AUTH_TOKEN` for DeepSeek, Kimi-Code, MiMo,
MiMo-Token-Plan, tokenbox), **opencode** `~/.local/share/opencode/auth.json` + `~/.config/opencode/opencode.json`,
**codex** `~/.codex/config.toml` (`model_providers.*.env_key` → resolve named env var).

Prioritized sources: (1) allowlisted env vars (`DEEPSEEK_API_KEY`, `MOONSHOT_API_KEY`, `MIMO_API_KEY`, `OPENAI_API_KEY`+`OPENAI_BASE_URL`),
(2) cc-switch DB, (3) opencode (`type:'api'` only, skip `oauth`), (4) codex `config.toml` env_key pointer, (5) aichat/Continue/llm/.env.
Match provider by **host** (`api.deepseek.com`→DeepSeek; `*.xiaomimimo.com`→MiMo; `api.kimi.com/coding`→Kimi→**force anthropic**; `tokbox-api.netease.im`→tokenbox);
dedup on (host, key-prefix+length); normalize endpoint to the full path. Cross-platform paths in the design source.

**Security (R5) — hard rules:** import **only** static keys to sanctioned OpenAI/Anthropic `api.*` endpoints.
**NEVER** read/import OAuth tokens — hard-skip `~/.claude/.credentials.json` (Anthropic ToS ban), `~/.gemini/oauth_creds.json`
(Google detect+ban 2026-03-25), `~/.config/github-copilot` (token-exchange), `~/.codex/auth.json` OAuth block (not sanctioned/fragile).
**Explicit consent** — no launch scan; a deliberate "Detect existing keys" action; per-item checklist with provenance + masked preview;
nothing written until confirmed; **manual paste is always primary**. Store secrets in OS secret store (DPAPI/Keychain/libsecret),
**never plaintext in config.json**; mask `prefix…last4` everywhere; never log full keys.

**UX:** Detect → found N>0: "本机发现 N 个可用密钥,是否导入?" checklist (provider · source · `sk-deep…••••`) → import selected
→ prefilled, masked, ready backend. Found 0: silent fallback to manual paste. Subscription vendors: passive "用官方 App / 贴开发者 key" note, no checkbox.

## Spec-first build steps (Law 1 + Law 2 + Law 6)

1. **spec/backends.json** — add `openai-http` + `anthropic-http` entries (shapes above).
2. **conformance/backend-requests.json** — add cases FIRST (done-criterion): `openai-http` → method POST, url `chat/completions`, header `Authorization: Bearer K`, body has model/role/`{prompt}`; `anthropic-http` → url `/messages` (NOT `chat/completions`), headers `x-api-key`+`anthropic-version`, body has `max_tokens`/model. Must pass on Win (dotnet) **and** macOS (swift).
3. **Code — the `{prompt}` plumbing (NOT one line — see audit §below).** Win: `ManifestHttpBackend` gains a `promptTemplate` ctor param + field (mirror `ManifestCliBackend`); `Vars()` adds `["prompt"]=PromptBuilder.Build(promptTemplate, text)`; call-site `TranslatorRegistry.cs:27` → `new ManifestHttpBackend(id, def, bc, tmpl)`; test helper `Tb.Http` + `BackendFromConfig`/`RunBackendRequests` must thread a template. macOS: `HttpBackend.buildCall` gains `promptTemplate` + calls `PromptBuilder.build`, threaded via `TranslatorRegistry.swift`/`HttpTranslator.init`, AND must prefer `config.endpoint` over `def["endpoint"]`. Note: `{prompt}` is a NEW body Vars key = the OUTPUT of PromptBuilder, **distinct** from PromptBuilder's own `{content}` input placeholder. Still generic (no switch(id)).
4. **config.json** — additive; `BackendConfig` already has Type/Endpoint/ApiKey/Model. Add a `protocol` field (`openai`|`anthropic`) the UI maps to the template. Leave the two templates un-seeded (created on add/import) to keep the backends count stable.
5. **Custom-provider UI** (Windows first): "+ 自定义 provider" → fields baseURL, model, key (masked), **protocol radio (OpenAI/Anthropic)**; + "Detect existing keys" button.
6. **Auto-discovery module** — separate read-only importer writing the same config shape; its own `conformance/credential-discovery.json` over fixtures asserting (source→provider, base_url→protocol, masked-prefix) and that OAuth fixtures are SKIPPED (the static/OAuth boundary becomes a cross-platform contract).
7. **PARITY.md** — rows: "Backends — openai-http / anthropic-http (generic HTTP LLM)", "Custom provider (baseURL+key+protocol)", "Credential auto-discovery (static-key, consent-gated)". Win 🚧→✅ when vectors green; macOS/Linux ⬜.

## Risks (carry into the audit)

- Kimi `/coding` 403 is a **client allow-list**, not "OpenAI forbidden" — `/messages` from a non-whitelisted app *could* still 403; treat HTTP-Kimi as best-effort, keep the `kimi` CLI as fallback, **do not forge User-Agent** (ToS).
- `{prompt}` is a JSON string leaf → multi-line CJK must be JSON-escaped (JsonNode handles it; the vector must assert escaped CJK survives).
- Auto-discovery: dedup same key across stores; tokenbox `sk-8266…`(/v1) ≠ `sk-06b6…`(responses) — different keys; map protocol strictly by host.
- cc-switch is a 3rd-party SQLite — open read-only/immutable, tolerate lock/schema drift, never write.
- Secret-store may be absent (headless Linux) → explicit 0600 fallback flagged less-secure; never silent plaintext.
- Endpoint `/v1` ambiguity (DeepSeek base vs `/v1`; Kimi `/coding` vs `/coding/v1/messages`) → normalize to full path on write.

## Audit (2026-06-22, 6-agent adversarial, vs real code) — **GO-WITH-FIXES** (authoritative; supersedes conflicting inline text)

CONFIRMED sound: both shapes interpret via the existing `ManifestHttpBackend` with no `switch(id)`; both `responsePath`
forms work in `ManifestEngine.Eval` (int-index + `arr[key=value]`, as doubao/google already use). Blocking fixes:

- **P0-1 `{prompt}` plumbing** — does not exist in the HTTP path on either platform → see corrected Step 3 (ctor+field+Vars+call-site+test-layer+macOS mirror).
- **P0-2 cross-platform JSON-escape divergence** — C# `JsonNode.ToJsonString()` escapes CJK as uppercase `\uXXXX`; Swift `JSONSerialization` emits raw UTF-8. A raw-CJK `bodyContains` passes on one runner, fails on the other. **Vectors must assert ASCII-only substrings both encoders agree on** (`"role":"user"`, `"stream":false`, `"max_tokens":4096`, escaped `\n`) + a NON-EMPTY `promptTemplate` so `{prompt}≠{text}` is pinned — OR normalize C# to `UnsafeRelaxedJsonEscaping` first, then assert raw CJK.
- **P0-3 custom-provider drop** — `TranslatorRegistry.Build` skips ids absent from the manifest. Need a **protocol→template fallback** (resolve missing id's def by `BackendConfig.protocol`) + SEED the two defs + macOS `buildCall` must prefer `config.endpoint`.
- **P0-4 secret storage** — R5 promised OS secret store; none exists, config writes **plaintext** today. → owner decision below.
- **P1s:** test-layer threading (`Tb.Http`/`BackendFromConfig` + a `promptTemplate` case field on BOTH runners); `{content}`≠`{prompt}` namespace; PARITY rows already exist (**flip** `PARITY.md:23-25`, don't add); spec anchors §6.x/§9 don't exist yet (add narrative to the 2026-06-17 design spec FIRST, Law 1); macOS endpoint-override; **SQLite mechanism** vs framework-only (decision below); cc-switch **static-vs-OAuth discriminator** (skip `api.anthropic.com`/`claude.ai` hosts + JWT/refresh-shaped tokens; SKIP-fixture); custom-provider UI is an **add-backend dialog + dynamic `_config.Backends.Keys`** (the fixed `BackendOrder` array hides custom ids), not just "add fields"; Law-4 — no version bump (protocol rides `[JsonExtensionData]` or a typed field mirrored to macOS in lockstep).
- **Non-blocking:** no `headersNotContains` in either runner (assert required headers positively, or add it shared); `BackendConfig` is at `Config/AppConfig.cs:61` (not `Models.cs`); re-verify the 2026 ToS facts before land.

### TWO OPEN OWNER DECISIONS (gate Phase 2 / auto-discovery)
1. **Secret storage posture (P0-4):** encrypt-at-rest (DPAPI/Keychain/libsecret — new code, also upgrades existing google/doubao keys) **vs** plaintext-at-rest + UI masking + loud consent disclosure (matches today's behavior).
2. **cc-switch SQLite (P1):** P/Invoke OS sqlite (`winsqlite3.dll`/`libsqlite3`, keeps framework-only) **vs** defer cc-switch and import only env + opencode JSON + codex TOML for v1 **vs** approve first NuGet (`Microsoft.Data.Sqlite`).

### Corrected landing order (Win-first, spec+vectors first)
(0) add §6.x/§9 narrative to the design spec + apply corrections + resolve the 2 decisions → (1) `spec/backends.json` openai-http+anthropic-http → (2) **shared harness change** (add `promptTemplate` case field; thread both dotnet+swift runners) → (3) conformance cases (RED, ASCII-only) → (4) Win `{prompt}` code → (5) macOS `{prompt}`+endpoint mirror → (6) build/test GREEN both runners (count-9 still passes, templates un-seeded) → (7) config protocol field + registry fallback (mirror macOS, round-trip assert) → (8) custom-provider UI (Win) → (9) auto-discovery importer + `credential-discovery.json` (static-vs-OAuth SKIP fixtures) → (10) storage decision enforced before any import writes a key → (11) flip `PARITY.md:23-25` Win ✅ as vectors green → (12) cross-review per `.hopper/AGENTS.md` (different channel; no self-review).

Phase 1 (steps 1–8, the HTTP backends + custom provider) is unblocked by the 2 decisions. Phase 2 (steps 9–10, auto-discovery) needs both.

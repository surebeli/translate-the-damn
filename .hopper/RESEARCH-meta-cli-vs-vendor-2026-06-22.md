# Research — meta-CLI (aichat / llm) vs per-vendor CLIs for translation backends

**Date:** 2026-06-22 · **Method:** 8-agent workflow (4 parallel deep-dives → adversarial verify of 3 crux claims → synthesis). ~400k tokens, 131 tool uses. Confidence: high.

## Question

Should backend integration keep calling each vendor's own CLI, or route through a unified meta-CLI —
[aichat](https://github.com/sigoden/aichat) (Rust) or [llm](https://github.com/simonw/llm) (Python)?
And if a meta-CLI: does it support both **subscription** and **API** modes, and can it import an existing
subscription's baseURL+key from local config?

## Bottom line — HYBRID (do NOT replace the per-vendor CLIs)

The per-vendor-CLI design exists to ride **flat-rate subscriptions** (claude.ai OAuth, ChatGPT login,
Copilot, Antigravity, Kimi Code) at **$0-at-the-margin**. Neither meta-CLI can carry those OAuth sessions —
they authenticate with **API keys** (pay-per-token). So a meta-CLI cannot replace the subscription CLIs
without destroying the core value. It only helps the **API-key / OpenAI-compatible long tail**.

- **Keep** all 8 subscription CLI backends as-is (claude, codex, copilot, agy, opencode, kimi, mimo).
- **For the OpenAI-compatible long tail** (DeepSeek, MiMo-API, Moonshot-API, future "base_url+key" providers):
  prefer **ONE generic `openai-compatible` HTTP backend** in `spec/backends.json` — zero runtime dep, and
  Law-6-visible (probe/parse/auth stay as inspectable data). This beats bundling a meta-CLI at all.
- **If** a bundled meta-CLI is ever wanted (broader provider matrix, request-patching, `--serve` normalizer):
  choose **aichat** (single static Rust binary, `--serve`, fast cold-start), **not** llm (Python runtime).

## Decision matrix

| Axis | vendor-CLI (current) | aichat (Rust) | llm (Python) |
|---|---|---|---|
| **Subscription (flat-rate, no API key)** — the core value | ✅ the whole point ($0/margin) | ❌ none (API-key aggregator only) | ⚠️ Copilot only (3rd-party plugin) |
| API / OpenAI-compatible long tail | ⚠️ bespoke entry per provider | ✅ 20+ providers + generic | ✅ plugins + `extra-openai-models.yaml` |
| Cross-platform / Windows bundling | n/a (each tool self-contained) | ✅ single static binary | ❌ Python runtime (uv ≈ +tens of MB) |
| Maintenance (long tail) | high (per-vendor quirks) | low | medium (plugin/uv fragility) |
| Law-6 fit (backends = inspectable data) | ✅ best | ⚠️ ok as 1 more entry; ❌ as a replacement | ⚠️ same |
| Output parsing | heterogeneous (already solved as data) | clean `-S` plain text | clean plain text |
| Latency | process spawn/call | fast + `--serve` option | Python cold-start, no server |

**aichat vs llm:** aichat wins decisively *for this project* on packaging (single binary vs Python) and
latency (`--serve`). llm's only edge — a Copilot subscription via `llm-github-copilot` — is redundant here
(we already have a dedicated `copilot` CLI on the same subscription).

## Q2 — do aichat/llm support BOTH subscription and API modes?

- **aichat:** API = ✅ (broad). **Subscription = ❌ across the board.** Maintainer's stance (issues #1387/#1391/#1030):
  no Copilot (no official API), no ChatGPT/Claude Pro/consumer-Gemini. Only OAuth-ish path = VertexAI ADC,
  which is **metered GCP billing, not flat-rate**.
- **llm:** API = ✅. **Subscription = ⚠️ exactly ONE provider** — GitHub Copilot via the third-party
  `llm-github-copilot` (device-flow OAuth, auto-refreshes the Copilot key). Claude Pro / ChatGPT Plus /
  consumer Gemini = ❌ (and Anthropic actively blocks subscription-OAuth in third-party clients in 2026).

→ For **this app's** subscriptions (Claude, ChatGPT, Antigravity, Kimi), **neither meta-CLI can ride them.**
Only the official vendor CLIs can.

## Q3 — can a subscription's baseURL+key be imported from local config?

**Static key — safe to offer "paste baseURL+key" (these are API providers, directly importable):**
- **DeepSeek** — `DEEPSEEK_API_KEY` + `https://api.deepseek.com` (OpenAI-compatible). No subscription/OAuth at all.
- **Xiaomi MiMo** — `MIMO_API_KEY` + `https://api.xiaomimimo.com/v1` (Token-Plan uses a *different* base
  `https://token-plan-cn.xiaomimimo.com/v1` — app must let the user pick).
- **Moonshot Kimi** — the Kimi Code/platform console mints a **static** key for third-party use +
  `https://api.moonshot.ai/v1` (even though the `kimi` CLI itself logs in via OAuth).

**OAuth token — NOT a clean importable static key; reuse is ToS-banned — do NOT scrape:**
- **Claude Pro/Max** (`~/.claude/.credentials.json` / macOS Keychain) — refreshing OAuth. **Anthropic Feb 2026
  ToS explicitly bans** using Free/Pro/Max OAuth in any other product.
- **ChatGPT Plus** (`~/.codex/auth.json`) — refreshing OAuth, scoped to Codex.
- **Gemini/Antigravity** (`~/.gemini/oauth_creds.json`) — refreshing OAuth. **Google bans + DETECTS**
  third-party proxying (enforced from 2026-03-25; real paying accounts banned).
- **GitHub Copilot** (`~/.config/github-copilot/apps.json`) — long-lived token exchanged at
  `api.github.com/copilot_internal/v2/token` for a short-lived bearer → OpenAI-compatible
  `https://api.githubcopilot.com`. Closest to reusable (the copilot.vim/aichat pattern) but a **two-step
  OAuth exchange, not a static key, and unsanctioned** → keep the dedicated `copilot` CLI.

**Net:** for the three OAuth majors, importing the local credential is both technically wrong (refreshing
token, breaks) and **against ToS / risks account bans**. Only DeepSeek/MiMo/Moonshot are clean static-key
imports — and those slot straight into a generic `openai-compatible` HTTP backend with **no meta-CLI at all**.

## Recommended architecture (Law-6-faithful)

Add ONE generic HTTP backend; keep subscription CLIs untouched:

```jsonc
"openai-compatible": {
  "kind": "http", "method": "POST",
  "endpoint": "{baseUrl}/chat/completions",
  "headers": { "Authorization": "Bearer {apiKey}", "Content-Type": "application/json" },
  "bodyTemplate": { "model": "{model}", "messages": [
    {"role":"system","content":"{system}"}, {"role":"user","content":"{text}"} ] },
  "responsePath": "choices[0].message.content",
  "defaults": { "system": "You are a professional translator. Output only the translation." }
}
```

One entry covers DeepSeek / MiMo / Moonshot / any OpenAI-shaped provider — `baseUrl`/`model`/`apiKey`
become `config.json` data. `google-v2` and `doubao` stay as their own HTTP entries (non-OpenAI shapes).
Optionally add ONE `aichat` CLI backend later (API-key only; never for subscription backends).

**Do NOT** route the subscription CLIs through a meta-CLI — that just relocates per-vendor branching into the
meta-CLI's opaque config where conformance vectors can't pin it (weakens Law-1/Law-2) and breaks subscription
monetization.

## Risks / caveats

- ToS/ban risk if anyone scrapes local OAuth stores (Anthropic Feb 2026 ban; Google detect+ban from 2026-03-25). Never do it.
- aichat `api_key_helper` (dynamic token from another CLI) is PR #1460, **open/unmerged** at last check — don't rely on it.
- DeepSeek deprecates legacy `deepseek-chat`/`deepseek-reasoner` ids 2026-07-24; MiMo Token-Plan base differs from the standard API.
- Version/tag for aichat unverified (GitHub API was rate-limited during research).

## Sources (selected)
aichat README/wiki/issues #1387/#1391/#1030/PR#1460; llm docs + `llm-github-copilot`; Anthropic/OpenAI/Google
auth docs; CLIProxyAPI / opencode-*-auth / copilot-api; DeepSeek/Moonshot/MiMo platform docs. Full list in the
workflow transcript.

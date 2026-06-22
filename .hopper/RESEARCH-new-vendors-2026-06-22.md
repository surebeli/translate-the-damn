# RESEARCH — three new CLI translation vendors + agy workaround re-research

**Date:** 2026-06-22 · **Author:** main session (synthesis of probe + adversarial verify passes)
**Status:** for-owner-approval (spec-first; **no spec/conformance/config edits yet**)
**Scope:** add `opencode`, `kimi`, `mimo` CLI backends to `spec/backends.json` + Windows `DefaultConfig`; re-decide the `agy` empty-stdout workaround.

> Process note (Constitution Law 1): nothing below has been written into `/spec` or `/conformance`.
> This is the pre-implementation synthesis. On approval, the spec/conformance edits land **first**,
> then the Windows interpreter/config catches up (the interpreter today still hardcodes the manifest —
> tracked PARITY task).

---

## 0. TL;DR

- **opencode** — verified live end-to-end (free model, $0). Invocation, prompt-as-positional-arg, `--format json` JSONL parse, `--dangerously-skip-permissions`, `--variant` effort all confirmed. **High confidence. Ship.**
- **kimi** — every flag verified via help + adversarial execution (no billable call). `-p` is self-contained (NO skip-perms flag; adding `--auto`/`--yolo` *errors*). One model, thinking always-on, no effort flag. **High confidence. Ship; default parse to `stream-json`.**
- **mimo** — OpenCode-derived; all flags/structure verified live, but **no real translation call was run**, so end-to-end stdout cleanliness is asserted-not-proven. **Medium confidence. Ship as `best-effort`; owner runs one real call to lock parse mode.**
- **agy** — root cause = upstream open bug (antigravity-cli #76: non-TTY stdout swallows the answer); 1.0.10 is already newest, no flag fixes it. **A viable Windows fix exists** (PTY wrapper: winpty `-Xallow-non-tty`, already installed with Git for Windows; or Headless-TTY via ConPTY). Verdict below.

---

## 1. Per-vendor summary table

| Vendor | Non-interactive invocation | Model flag + default | Effort | Skip-perms flag | Auth probe (offline) | Confidence | probe ⇄ verify disagreements |
|---|---|---|---|---|---|---|---|
| **opencode** | `opencode run "{prompt}" -m {model} --format json --dangerously-skip-permissions` (prompt = **positional** arg to `run`) | `-m {model}` · default `deepseek/deepseek-chat` | `--variant {tier}` — **provider-specific, validated server-side**; append only when set, never pin a cross-provider default | `--dangerously-skip-permissions` (guards against any tool-permission hang) | `opencode auth list` → `"… N credentials"` footer + provider rows | **high** (verified live, $0) | (1) model catalog **stale** → enumerate at runtime via `opencode models`, don't hardcode. (2) NEVER use `-p`/`--prompt` on `run` (`-p`=`--password` there). (3) probe `successSignatures:["credentials"]` substring-matches BOTH "2 credentials" AND "0 credentials" → **fail-wins ordering required** (eval `failSignatures:["0 credentials"]` first). |
| **kimi** | `kimi -p "{prompt}" --model {model} --output-format {fmt}` | `--model {model}` · default `kimi-code/kimi-for-coding` (only model) | **none** — no per-call effort flag; thinking is config-driven always-on | **""** (none — and `-p` is *mutually exclusive* with `--auto`/`--yolo`/`--plan`; adding any errors out) | `kimi provider list` → `managed:kimi-code … source=oauth` | **high** (help + adversarial exec; no billable call) | None material. Nits: probe latency ~1.4 s (not the proposed ~560 ms) → characterize "sub-2s offline". The text-mode "• bullet + 2-space wrap" parse caveat is **doc-only, unverified** → default parse to **`stream-json`** instead. `telemetry=true` in config (awareness). |
| **mimo** | `mimo run "{prompt}" --model {model} --dangerously-skip-permissions` (prompt = **positional**; bare `mimo` launches the **TUI → hangs**) | `--model {model}` · default `xiaomi/mimo-v2.5-pro` | `--variant {tier}` — provider-specific "reasoning effort"; repo maps `xhigh → max` | `--dangerously-skip-permissions` (REQUIRED; `--never-ask` does NOT cover permissions) | `mimo providers whoami` → `Provider: MiMo` + `User ID:` | **medium** (flags verified live; real translate call NOT run) | `effortTiers` were listed as a closed enum but `run --help` only **exemplifies** `high/max/minimal` → relabel as "examples, not enumerated". `failSignatures` (`0 credentials`/`not logged in`) are **guesses** (only the authed success path was observable). Parse mode (`default` ANSI-strip vs `--format json`) **unconfirmed** — owner must run one call. |

Common to all three (same caveat as `claude`): **spawn from a neutral CWD** so the CLI doesn't load the repo's `AGENTS.md`/project context into a translation prompt. All three strip ANSI before signature-matching (reuse the existing `ansi-stripper` vector).

---

## 2. Ready-to-paste `spec/backends.json` snippets

These follow the existing CLI contract (`kind`/`command`/`promptVia`/`args`/`argsAppend`/`defaults`/`effortTiers`/`probe`/`parse`/`auth`/`status`/`notes`) and the `{prompt}` placeholder convention used by `copilot`/`agy`.

### 2a. opencode

```json
"opencode": {
  "kind": "cli",
  "command": "opencode",
  "promptVia": "arg",
  "args": ["run", "{prompt}", "-m", "{model}", "--format", "json", "--dangerously-skip-permissions"],
  "argsAppend": [ { "when": "reasoning", "args": ["--variant", "{reasoning}"] } ],
  "defaults": { "model": "deepseek/deepseek-chat", "timeoutSec": 60 },
  "effortTiers": ["none", "minimal", "low", "medium", "high", "xhigh", "max"],
  "probe": { "args": ["auth", "list"], "network": false, "retries": 1, "successSignatures": ["credentials"], "failSignatures": ["0 credentials"] },
  "parse": { "mode": "stdout-clean", "jsonl": true, "jsonEvent": "type==text -> part.text (concat all in order); step_finish=cost/tokens; error=fail" },
  "auth": "opencode auth login (creds in ~/.local/share/opencode/auth.json) or provider env keys",
  "status": "best-effort",
  "notes": "sst/opencode TS edition (v1.17.7): prompt is a POSITIONAL arg to the `run` subcommand (NEVER -p/--prompt on run; -p there = --password). Model is provider/model — enumerate live via `opencode models` (catalog is DYNAMIC; do not hardcode). --variant tiers are PROVIDER-SPECIFIC, validated server-side (OpenAI: none/minimal/low/medium/high/xhigh; Anthropic: high/max; Google: low/high) → append only when set, never pin a cross-provider default. --dangerously-skip-permissions guarantees no permission-prompt hang. --format json → JSONL; answer = every type==text event's part.text concatenated; logs stay off stdout unless --print-logs. Spawn from a NEUTRAL CWD (loads current dir's AGENTS.md otherwise). PROBE: successSignatures:['credentials'] matches BOTH '2 credentials' AND '0 credentials' → classifier MUST fail-win on '0 credentials' (eval failSignatures first). Verified live $0 on opencode/north-mini-code-free."
}
```

### 2b. kimi

```json
"kimi": {
  "kind": "cli",
  "command": "kimi",
  "promptVia": "arg",
  "args": ["-p", "{prompt}", "--model", "{model}", "--output-format", "{outputFormat}"],
  "defaults": { "model": "kimi-code/kimi-for-coding", "outputFormat": "stream-json", "timeoutSec": 90 },
  "effortTiers": [],
  "probe": { "args": ["provider", "list"], "network": false, "retries": 1, "successSignatures": ["source=oauth", "managed:kimi-code"], "failSignatures": ["models=0", "No providers configured"] },
  "parse": { "mode": "stdout-clean", "streamJson": { "ndjson": true, "pick": "messages[role=assistant && !tool_calls].text" }, "textFallback": { "stripLeadingBullet": "• ", "dedentContinuation": 2 } },
  "auth": "Kimi Code OAuth (device-code: `kimi login`); creds at ~/.kimi-code/credentials/kimi-code.json",
  "status": "best-effort",
  "notes": "Moonshot Kimi Code CLI (kimi.exe v0.17.1; NOT legacy 'kimi-cli'). `-p` runs ONE prompt non-interactively, self-contained: NO skip-permissions flag, and -p is MUTUALLY EXCLUSIVE with --auto/--yolo/--plan (adding any → exit 1). Only one model: kimi-code/kimi-for-coding (thinking always-on; NO per-call effort flag → effortTiers []). DEFAULT parse = --output-format stream-json (NDJSON; concat role==assistant messages without tool_calls) — robust and verified-shape. text mode is a TRANSCRIPT (assistant lines prefixed '• ', wrapped lines indented 2 spaces) — kept only as a doc-only fallback (UNVERIFIED without a billable call). Thinking/tool-progress go to stderr. Probe `kimi provider list` is offline, sub-2s, non-billable; do NOT gate on `kimi doctor` (validates config.toml syntax, not auth). Spawn from a neutral CWD."
}
```

### 2c. mimo

```json
"mimo": {
  "kind": "cli",
  "command": "mimo",
  "promptVia": "arg",
  "args": ["run", "{prompt}", "--model", "{model}", "--dangerously-skip-permissions"],
  "argsAppend": [ { "when": "reasoning", "args": ["--variant", "{reasoning}"] } ],
  "defaults": { "model": "xiaomi/mimo-v2.5-pro", "timeoutSec": 90 },
  "effortTiers": ["minimal", "low", "medium", "high", "max"],
  "probe": { "args": ["providers", "whoami"], "network": false, "retries": 1, "successSignatures": ["Provider: MiMo", "User ID:"], "failSignatures": ["not logged in", "no provider"] },
  "parse": { "mode": "stdout-clean", "jsonEvent": "assistant message -> text parts (only when --format json)" },
  "auth": "Xiaomi MiMo API key in ~/.local/share/mimocode/auth.json (set via `mimo providers login`)",
  "status": "best-effort",
  "notes": "OpenCode-derived 'mimocode' (v0.1.1). NON-INTERACTIVE = `mimo run <message>`; bare `mimo` launches the TUI and HANGS. Prompt = positional arg (no stdin-dash). --dangerously-skip-permissions REQUIRED or a tool-permission prompt blocks → empty stdout (NOTE: --never-ask does NOT cover permissions). --variant carries provider reasoning effort — `run --help` only EXEMPLIFIES high/max/minimal (low/medium plausible but UNVERIFIED — treat list as examples, not a closed enum); repo maps xhigh→max; append only when set. Default --format is human text → parse stdout-clean (ANSI/clack box chars stripped); if chrome leaks, switch to --format json and concat the final assistant message's text parts. Optional hardening: --pure (no external plugins) + neutral CWD (project memory under the share dir could leak). NOT VERIFIED: a real translation call → parse.mode and exact json field names pending one owner smoke test. Confidence medium."
}
```

> **Effort placeholder name:** existing CLI backends append effort via `{reasoning}` (see `claude`/`codex`/`copilot`). opencode/mimo reuse `{reasoning}` for `--variant`. kimi has no effort knob.

---

## 3. DefaultConfig additions (Windows `DefaultConfig.cs`)

Three new `Backends` entries + three `ModelCatalog` entries. **Catalogs are pinned snapshots** (the file's own doc says it's intentionally temporary / may be replaced by a dynamic catalog) — for opencode/mimo the live `models` command is authoritative, so keep the pinned list short and note it's a snapshot.

```csharp
// --- Backends dictionary (append) ---
["opencode"] = new() { Type = "cli", Command = "opencode", Model = "deepseek/deepseek-chat", TimeoutSec = 60 },
["kimi"]     = new() { Type = "cli", Command = "kimi", Model = "kimi-code/kimi-for-coding", OutputFormat = "stream-json", TimeoutSec = 90 },
["mimo"]     = new() { Type = "cli", Command = "mimo", Model = "xiaomi/mimo-v2.5-pro", TimeoutSec = 90 },

// --- ModelCatalog dictionary (append) — snapshots; opencode/mimo enumerate live ---
["opencode"] = new() { "deepseek/deepseek-chat", "deepseek/deepseek-reasoner", "deepseek/deepseek-v4-pro", "tokenbox/glm-5.2", "tokenbox/kimi-k2.6", "xiaomi-token-plan-cn/mimo-v2.5-pro" },
["kimi"]     = new() { "kimi-code/kimi-for-coding" },
["mimo"]     = new() { "mimo/mimo-auto", "xiaomi/mimo-v2-flash", "xiaomi/mimo-v2-pro", "xiaomi/mimo-v2.5", "xiaomi/mimo-v2.5-pro", "xiaomi/mimo-v2.5-pro-ultraspeed" },
```

**`backends` count changes 6 → 9.** That breaks `config-defaults.json` assert `{ "path": "backends", "count": 6 }` on every platform — so the count assertion must be bumped to **9** in the same spec-first commit (see §4).

> `ActiveBackend` stays `claude` (no change to the default backend; these are additive). Effort-tier defaults are **not** stored per-backend in `DefaultConfig` (effort is appended only when the user sets a tier in the UI), so no `Reasoning` field is seeded for the new entries — matching `copilot`/`claude`.

---

## 4. Conformance + PARITY plan (spec-first ordering)

**Step 1 — spec (`spec/backends.json`):** add the three `backends` entries from §2.

**Step 2 — conformance vectors (edit, in the SAME commit, before any C#):**

| Vector | Change |
|---|---|
| `config-defaults.json` | bump `{ "path": "backends", "count": 6 }` → **`9`**. Optionally add `containsItem` asserts for the three new catalogs (e.g. `modelCatalog.kimi` containsItem `kimi-code/kimi-for-coding`). |
| `effort-tiers.json` | add cases: `opencode` → `["none","minimal","low","medium","high","xhigh","max"]`; `mimo` → `["minimal","low","medium","high","max"]`; `kimi` → `[]` (mirrors `agy`, which validates the empty-tier path). |
| `doctor-probe.json` | add the three `probe` cases (args + signatures from §2). All three are `network:false`. |
| `doctor-classify.json` | add a regression case for the **opencode fail-wins-on-"0 credentials"** trap (substring `"credentials"` ⊂ `"0 credentials"`) — analogous to the existing codex `"not logged in" ⊄ "logged in using"` and agy success-wins cases. This is the one genuinely new classifier behavior. |
| `ansi-stripper.json` | **no change** — existing cases already cover the clack box-drawing / SGR codes all three emit (box chars are non-ESC UTF-8 and are handled by the stdout-clean line logic, ESC sequences by the stripper). |
| `backend-requests.json` | **no change** — that vector is HTTP-only; the three new backends are CLI. |
| `prompt-builder.json` | **no change** — prompt construction is backend-agnostic. |

> No NEW vector files are needed. The new backends slot into the existing manifest-driven vectors (`effort-tiers`, `doctor-probe`, `doctor-classify`, `config-defaults`). That's the manifest's whole point — adding a backend is data, not a new contract.

**Step 3 — Windows impl (after vectors are red):** add the `DefaultConfig` entries from §3; if/when the interpreter is refactored to read the manifest (tracked Q2 task), these become free; until then the adapter list must include the three commands. Run `dotnet run --project platforms/windows/tests/TranslateTheDamn.Tests` until `config-defaults` + `effort-tiers` + `doctor-probe` + `doctor-classify` are green.

**Step 4 — PARITY.md:** the existing "Backends — copilot, agy (CLI)" pattern is the model. Add a row:

```
| Backends — opencode, kimi, mimo (CLI) | §6 | `spec/backends.json` + `effort-tiers` + `doctor-probe` | 🚧 | ⬜ | ⬜ |
```

Mark Win `🚧` until the config + doctor vectors pass on Win CI, then `⚠️`/`✅` (these are `status:"best-effort"` like copilot/agy, so `⚠️` is the realistic terminal state until a real translate call is logged). macOS/Linux `⬜`. **Same MAJOR.MINOR rule (Law 3):** if these ship on Win they must be declared+spec'd for macOS too (even if `⬜`), so the macOS port picks them up — record the gap in PARITY rather than diverging the feature set.

---

## 5. agy verdict — IS there a viable fix?

**YES — viable Windows fix exists; recommend a PTY wrapper, NOT a flag change.**

**Root cause (re-confirmed):** `agy -p` completes a full model round-trip but **suppresses stdout whenever stdout is non-TTY** (pipe/redirect/spawned subprocess) — upstream **open bug antigravity-cli #76**. Exit code is 0; the log holds only operational events, never the answer. Local `agy` is **1.0.10 = newest release** (no 1.0.11 exists), so there is **nothing to upgrade to**, and **no `--output-format`/`--output` flag works** (those are #76 *proposals*, rejected at runtime as "flags provided but not defined"). This is distinct from the keyring "not logged into Antigravity" cold-start race (already handled by the success-wins classifier).

**Recommended exact change** — wrap `agy -p` in a pseudo-console so `isatty(stdout)` is true:

1. **Primary (zero-install):** winpty is already on this box at `D:\Program Files\Git\usr\bin\winpty.exe`. Plain piping fails ("stdout is not a tty") — add the undocumented flag:
   ```
   winpty -Xallow-non-tty agy -p "<prompt>" --dangerously-skip-permissions > out.txt
   ```
   then strip ANSI + CR (reuse the `ansi-stripper` vector).
2. **Fallback (if winpty garbles the Go TUI output):** `winget install Revoconner.HeadlessTTY` (purpose-built ConPTY; Win10 1809+; this box is Win11), then
   ```
   headless-tty.exe -- agy -p "<prompt>" --dangerously-skip-permissions
   ```

**Manifest impact if adopted:** `agy.command` would become the PTY wrapper with `agy` as a sub-arg (e.g. `command:"winpty"`, `args:["-Xallow-non-tty","agy","-p","{prompt}","--dangerously-skip-permissions",…]`), with a Windows-specific `knownInstallPaths`/wrapper note. The existing log-probe + `stdout-clean`/ANSI-strip parse stay. Keep `status:"best-effort"` and the `gemini` fallback.

**Decision recommendation for the owner — pick one:**
- **(A) Wire the winpty wrapper** into the agy manifest entry (low effort, zero-install, makes agy actually return text on Windows). Requires **one non-billable PTY smoke test** to confirm the wrapper before merge. *Recommended if agy must stay a first-class backend.*
- **(B) Leave agy as-is** (`best-effort`, falls back to `gemini`) and **prefer the three new vendors + the gemini API-key path** for real coverage. The gemini fallback prints cleanly to non-TTY stdout with `-o text` **but only on a paid AI Studio key / Vertex** (free individual OAuth was deactivated 2026-06-18 → `IneligibleTierError`); a free key still fails. *Recommended if billing-free, low-touch is preferred — agy stays a documented-degraded backend.*

**Not viable (do not pursue):** `ANTIGRAVITY_API_KEY` headless auth — unverified open feature request (#78), and even if it fixed the keyring race it would **not** fix the stdout drop. `script`/PTY trick — no `script` binary on Windows (Linux/macOS-CI only).

**Net:** *fixable on Windows via a PTY wrapper (A); otherwise upstream-blocked for non-TTY stdout and the recommendation is to lean on opencode/kimi/mimo + a paid gemini key (B).*

---

## 6. Open questions + confidence flags

| # | Question | Owner action | Blocks |
|---|---|---|---|
| 1 | **mimo** real-call parse mode: is `--format default` (ANSI-stripped) clean enough, or is `--format json` required? Exact json assistant-message field names? | One real `mimo run` translation from a neutral CWD. | Locking mimo `parse.mode`; confidence medium→high. |
| 2 | **kimi** text-mode "• bullet + 2-space wrap" transcript caveat is doc-only. | Defaulting to `stream-json` (recommended in §2b) sidesteps it — no call needed unless text mode is wanted. | Only the text fallback, not the default path. |
| 3 | **opencode** `--format json` occasionally exits before the final `step_finish` (upstream #26855). | Parser must tolerate a missing trailing `step_finish` — collect `text` parts as they arrive, don't require the final event. | Robustness only; answer still extractable. |
| 4 | **agy** which option — (A) winpty wrapper or (B) leave-as-is + new vendors? | Owner decision; if (A), run one non-billable PTY smoke test first. | agy manifest change. |
| 5 | **mimo** `effortTiers` low/medium are unverified (help only exemplifies high/max/minimal). | Treat as examples; functionally harmless (`--variant` appended only when set). | Cosmetic; no functional risk. |
| 6 | **Same-version cross-platform (Law 3):** shipping these on Win obligates macOS/Linux to at least declare+spec them. | Add the PARITY row with macOS/Linux `⬜` in the spec-first commit. | Parity-drift gate. |

**Overall confidence:** opencode **high** · kimi **high** · mimo **medium** (pending 1 call) · agy fix **high** (root cause + wrapper both confirmed). **No billable model calls were made** in this research (opencode's live check used a $0 free model; kimi/mimo were help+structure only).

# RESEARCH — Per-vendor "Model Doctor" + Per-vendor Effort-Tier Selector (Windows / WPF)

Date: 2026-06-22 · Author: lead engineer (synthesis) · Audience: human owner (design approval gate)
Scope: Windows .NET 9 / WPF Settings window. Feature pair — (1) a per-vendor **doctor** (connectivity / auth / model-listing probe) and (2) a per-vendor **effort-tier selector** (replacing today's codex-only free-text "推理强度" box).

Source basis: live CLI probes + independent verify pass + integration-surface read + web docs (all four input blocks), cross-checked against repo source. Every load-bearing file:line below was opened and confirmed during this synthesis.

---

## 1. Executive summary

- **The doctor must be a Core service, not per-vendor C#.** Backends are already 100% data-driven: `TranslatorRegistry.Build` (TranslatorRegistry.cs:16) constructs one generic `ManifestCliBackend`/`ManifestHttpBackend` per entry in `spec/backends.json`. Adding doctor/effort logic the right way (Constitution Law 6) means **extending the manifest schema + the generic interpreter**, never branching on `id == "codex"`. The codebase already has one Law-6 smell to fix, not extend: `RowReasoning` visibility is a hardcoded `isCodex` flag (SettingsWindow.xaml.cs:93).
- **No vendor can enumerate models non-interactively.** All four CLIs (claude, codex, copilot, agy) expose model lists ONLY through an interactive `/model` picker. There is no `models`/`list-models`/`--list-models` stdout command on any of them; probing for one either hangs (claude treats `models` as a prompt and blocks; agy `models` hung at exit 124 on this machine) or aborts (codex "stdin is not a terminal"). **Model-listing is out of scope for v1** — the app's static `ModelCatalog` (DefaultConfig.cs:37-45) stays the source. The current spec doc explicitly says "no CLI can list models reliably," so adding live listing would require a spec change first.
- **Connectivity/auth IS probeable cheaply for claude and codex, but only as a local credential check** — not a true end-to-end probe. `claude auth status --json` (loggedIn:true, ~449ms, exit 0) and `codex login status` / `codex doctor --json` are non-interactive and safe. copilot and agy have **no** non-interactive auth-status command; their only true auth signal is a billable `-p` run (forbidden here), so they degrade to "installed / auth confirmed on first translation."
- **Effort is two different mechanisms across vendors, and today only codex actually consumes it.** codex: `-c model_reasoning_effort="{reasoning}"` (TOML override, no client-side validation). claude/copilot: a real `--effort` flag exists but the app's manifest args **never pass it** (claude's effective "tier" is the model alias haiku<sonnet<opus<fable). agy: no flag at all — effort is a label suffix on the model ("Gemini 3.5 Flash (High)"), chosen at model-pick time. So a *per-vendor* effort selector needs a **manifest-declared allowed-tiers list** (new field), because the manifest currently declares only a single default `reasoning` value, and only for codex.
- **The agy "auth failed on first call" is a known transient keyring cold-start race, NOT a logout** — but the verify pass refutes the naive "trust the 2nd call" fix and partly refutes the "exit0+empty-stdout" premise (on this machine bare `agy` HUNG at exit 124 with empty stdout+stderr, it did not return exit 0). Recommended handling: **bounded retry that reports the FINAL state** + agy-signature classification + keep the two Windows agy quirks (empty-stdout `-p` bug vs keyring auth) distinct. Confidence medium.
- **The Windows "auth lamp" is fake today.** `LblAuth` (SettingsWindow.xaml:79) is a static text label computed synchronously by `AuthHint()` (xaml.cs:135-145) doing only a PATH/ApiKey-empty check. The richer async contract `ITranslator.CheckAuthAsync → AuthState{Ready,Unknown,Missing}` exists (ITranslator.cs:11, Models.cs:16-24) but is **unused by the Windows UI** — and for CLI it only checks PATH (ProcessTranslator.cs:105-111), never runs the binary. macOS already calls `refreshAuthHint()` — this is a Windows parity gap.
- **This is shared, user-visible behavior → spec-first.** Both features touch §6 (backends) and §9 (settings). Per Law 1/2/3: update `/spec` + add/extend `/conformance` vectors BEFORE Windows code, and either land matching macOS support or record the gap in `PARITY.md`. A Windows-only ship silently breaks parity.
- **Effort-tier selector is the cheap, high-value half; doctor is the bigger lift.** The Reasoning pipe is already end-to-end wired (TextBox → `BackendConfig.Reasoning` → `vars["reasoning"]` → `{reasoning}` token), so the selector is mostly a TextBox→ComboBox swap + a manifest tier list. The doctor needs a new Core probe primitive (the manifest has no probe/doctor verb today) and async UI plumbing (SettingsWindow has no `TranslatorRegistry` reference yet).

---

## 2. Per-vendor findings table

| Vendor | Connectivity / auth check (non-interactive) | Can enumerate models? (how) | Effort param (how passed) | Effort tiers | Confidence |
|---|---|---|---|---|---|
| **claude** | `claude auth status --json` → exit 0, `loggedIn:true`, ~449ms. **Local credential check only** (no network/E2E). Do NOT use `claude doctor` (auto-updater health only). | **No.** No `models`/`list-models`/`--list-models`. `claude models` is treated as a prompt and **HANGS** (must kill). Catalog is static: DefaultConfig.cs:39 `[haiku,sonnet,opus,fable]`. | App passes **no** `--effort`. Effective tier = model alias (haiku<sonnet<opus<fable). `--effort` flag exists globally but `{reasoning}` is absent from claude args → computed-but-unused. | CLI flag tiers: low/medium/high/xhigh/max (UNUSED by app). App tier = model alias. | **high** |
| **codex** | `codex login status` → "Logged in using ChatGPT"; or `codex doctor --json` → `overallStatus` + `auth.credentials` + `network.provider_reachability` (403 = healthy). Doctor **touches the network** (live WS handshake). | **No.** No `models`/`list`/`--list-models`; `codex models` aborts "stdin is not a terminal". `doctor config.load` reports only the single configured model. Catalog static: DefaultConfig.cs:40. | `-c model_reasoning_effort="{reasoning}"` (TOML override on `codex exec`). **The only vendor the app actually threads effort to.** No client-side validation (`bogus` still loads ok). | low (default) / medium / high / xhigh (names from project routing table, NOT CLI-confirmed). | **high** |
| **copilot** | **No auth-status/doctor subcommand.** `copilot --version`/`version` are exit-0 but only prove the binary + general internet (update channel), NOT Copilot auth. True auth needs a billable `-p` run (skipped). Today: PATH-presence only. | **No.** `copilot models` prints top-level help; `--model` w/o value → "argument missing". Static/curated only. | `--effort`/`--reasoning-effort <level>` CLI flag. **NOT in manifest args today** → adding effort = extend `spec/backends.json` + interpreter. (`--allow-all-tools` also missing — likely tied to Win `-p` no-output bug #1181.) | none/low/medium/high/xhigh/max (verified verbatim from `--help`). | **high** |
| **agy** | **No auth/login/status subcommand.** Inspect cred files `%USERPROFILE%\.gemini\oauth_creds.json` + `google_accounts.json` (offline), OR a `-p` liveness probe diagnosed via the **log** (success markers: "authenticated via keyring"/"authenticated successfully as"/cloudcode-pa). User IS authed (surebeli@gmail.com). | **No (reliably).** `agy models` is the documented command but on Windows non-TTY it **hung** (exit 124, empty stdout+stderr) — VERIFY pass refutes the probe's "exit 0 empty stdout". Live-auth-gated anyway. Catalog static: DefaultConfig.cs:42. | **No flag.** No `--effort`/`--reasoning`. Effort = model-label suffix ("Gemini 3.5 Flash (High)"), chosen at `--model`/picker time. App passes neither model nor effort to agy today (args are just `-p {prompt} --log-file {logFile}`). | Low/Medium/High (Gemini); "(Thinking)" for Claude variants. Exact `--model` string per tier **unverified**. | **medium** (effort=label & exact strings low) |

### Where probe and verify DISAGREED (important)

1. **agy `agy models` exit code — REFUTED.** Probe claimed "EXIT=0, empty stdout/stderr (non-TTY stdout drop)". Verify ran it 3× (25/30/60s) and every run **HUNG → killed at exit 124**, empty stdout AND stderr; a `-p` probe with abs log path also hung (exit 124, zero-byte log). Functional conclusion (not machine-enumerable from non-TTY) holds and is *worse* than stated. **Doctor implication:** an agy probe can produce an empty log to diagnose; the `logDiagnosis = "exit0+empty-stdout+auth-error-in-log"` rule's "exit0" premise is unreliable — must rely on the process kill-ceiling and treat hang/empty as best-effort.
2. **codex doctor `overallStatus` — CORRECTED.** Probe said `overallStatus=ok`. Verify: on this machine it is **`warning`** (driven by installation/updates checks: "npm root -g failed"), and only flips to `ok` when a `-c` override is present. **Doctor implication:** parse `auth.credentials.status` + `network.provider_reachability.status` specifically; treat top-level `warning` as non-fatal, NOT an auth/connectivity failure.
3. **codex version — CORRECTED.** Probe headline "active exe self-reports 0.140.0" is wrong; running binary is **0.131.0** (both `--version` and doctor `codexVersion`/`runtime.provenance.version`). The 0.140.0 was `updates.status["cached latest version"]` (update-availability), not the running binary. "Multiple codex binaries on PATH" is otherwise true.
4. **codex effort flag set — CONFLICT with web block.** Web docs claim a `-e`/`--reasoning-effort` launch flag and a `minimal` tier; verify confirms **this build (0.131.0) has NO such flag** — config-override (`-c`) is the only mechanism. Use the `-c` form (matches `spec/backends.json` codex args verbatim).
5. **claude `--json` redundant** (it's the default for `auth status`) — harmless, keep it for stability. `haiku` alias is app-catalog-sourced, not CLI-advertised.

---

## 3. The agy "auth-failed-on-first-call" quirk

### Root cause (agreed by both verify passes; confidence **medium**)
agy (Google Antigravity CLI, Go binary, Gemini-family, coexists with legacy `gemini`) cold-boots a language-server on every invocation. It reads its OAuth token from the OS secure store gated by a **hardcoded ~1s keyring read timeout** (reported `keyring.go:89`). On the first call of a session the keyring daemon is cold; when the 1s context expires agy logs `keyringAuth: timed out after 1s, skipping keyring auth` then `You are not logged into Antigravity` and proceeds as if logged out. ~300ms later (observed 502→824ms in `cli-20260622_025332.log`) the chain completes: `ChainedAuth: authenticated via keyring` / `OAuth: authenticated successfully as surebeli@gmail.com`. So the first-call failure is a **token-STORE read race, not expired/absent credentials**. (Local evidence: `oauth_creds.json` has access+refresh+expiry; `google_accounts.json` active = surebeli@gmail.com.)

**The current Core bug this exposes (CONFIRMED at ProcessTranslator.cs:79-92):** when stdout is empty, `Classify()` builds a lowercased blob of stdout+stderr+log and calls `LooksLikeAuthError` (lines 88-92). `"not logged in"` IS a substring of `"you are not logged into antigravity"`, so the transient startup lines **false-positive AuthFail** whenever stdout is empty. Not yet fixed.

### Chosen robust handling (verify pass overrides the probe's "trust 2nd call")
The premise "1st fails, 2nd always succeeds" is **partly refuted**: issues #85/#88 + the WSL thread report the keyring failing *consistently* on some setups (headless WSL has no keyring), which never self-clears. So blanket "ignore first auth-fail" would mask genuine persistent logouts. Adopt, in order:

1. **Bounded retry, report the FINAL state.** Run the auth/probe up to 2–3 times with a short backoff > 1s (to outlast the keyring window). SUCCESS if any attempt passes; **degraded/transient warning** if an early attempt failed but a later one passed (surface it, don't silently drop it); **HARD FAIL** only if all attempts fail.
2. **Signature-match, don't blanket-ignore.** Label the keyring / "not logged into Antigravity" signature as "keyring read timed out (transient cold-store), not a logout" **only when a later attempt actually succeeds**. If it persists across all attempts → real login/keyring-infra problem → prompt re-login + point at the file-store / `AGY_OAUTH_TOKEN` escape hatch.
3. **Keep agy's two Windows failure modes distinct.** empty-stdout-with-no-auth-error → the `-p` no-output bug → fall back to `gemini`. auth-error-in-log → the keyring path above. Conflating them sends users to the wrong fix.
4. **Prefer state inspection over a sleep loop.** Where possible check the persisted cred file / honor `AGY_OAUTH_TOKEN` rather than relying on timing. Consistent with the repo's conservative posture (`CheckAuthAsync` returns Unknown rather than hard-asserting; the `gemini` fallback already ships). **NOT** a token-refresh sleep loop (this is a keyring READ timeout, not OAuth refresh latency).

### Alternatives considered
- **(A) Warm-up + retry-once** — cheap, clears the macOS cold-daemon case, but its self-clear premise is unverified for WSL/persistent cases → false-green risk unless attempt-2 failure is surfaced loudly.
- **(B) Ignore-first-authfail heuristic** — rejected as primary; safe only paired with "and a later attempt succeeded."
- **(C) Escape-hatch / state inspection** — strongest signal-to-noise (cred file / `AGY_OAUTH_TOKEN` / raise timeout) but version-gated (file-store fix landed ~agy v1.0.1 per the WSL thread); detect version, fall back to bounded retry on older builds.
- **(D) Lean on the existing `gemini` fallback** — sidesteps agy auth for *throughput*, but a doctor should still diagnose agy itself, not just say "use gemini".
- **(E) Token-refresh sleep loop** — explicitly rejected (wrong failure model).

**Confidence: medium.** Mechanism agreed; the specific `keyring.go:89` line + ~1s constant + issue numbers (#57/#85/#88) are external/unverifiable from this repo. **Sources:** github.com/google-antigravity/antigravity-cli (issues #57/#85/#88), discuss.ai.google.dev WSL auth thread, github.com/google-gemini/gemini-cli discussion #27274, aibuilderclub.com agy guide; local: `cli-20260622_025332.log`, `oauth_creds.json`, `google_accounts.json`.

---

## 4. Integration plan (exact files + insertion points)

### 4.1 Effort-tier ComboBox (the cheap half)
The Reasoning pipe already runs end-to-end: `TxtReasoning` → `BackendConfig.Reasoning` (AppConfig.cs:68) → `ManifestCliBackend.Reasoning` (ManifestCliBackend.cs:28, falls back to `def.DefaultString("reasoning")`) → `vars["reasoning"]` (cs:42-47) → `{reasoning}` token in codex args (backends.json:19). Pinned by config-defaults.json:12 and Program.cs:139.

Swap to a ComboBox at these exact touchpoints:

1. **XAML** — `SettingsWindow.xaml:117-124` (`RowReasoning`). Replace `<TextBox x:Name="TxtReasoning"/>` with `<ComboBox x:Name="CmbReasoning" Height="28" IsEditable="True"/>` (mirror `CmbModel` at xaml:87; `IsEditable="True"` preserves the opaque-string contract so config-defaults.json:12 `"low"` and Program.cs:139 stay green).
2. **Load** — `SettingsWindow.xaml.cs:98-101 & 106`: in `LoadBackendFields`, populate `CmbReasoning.Items` from the manifest's per-backend tier list (see schema below), then `CmbReasoning.Text = bc.Reasoning ?? <manifest default>`. (Today line 106 sets `TxtReasoning.Text`.)
3. **Flush** — `SettingsWindow.xaml.cs:129`: replace `bc.Reasoning = NullIfEmpty(TxtReasoning.Text)` with `... NullIfEmpty(CmbReasoning.Text)` (still in the CLI branch).
4. **Visibility** — `SettingsWindow.xaml.cs:93` `Show(RowReasoning, isCodex)`: drive from **"manifest declares effort tiers for this backend"**, NOT the hardcoded `isCodex` flag (removes a Law-6 smell). Row shows for any backend whose manifest entry has a non-empty `effortTiers`.

No Core changes needed for the selector itself — `Reasoning` already flows. Only the manifest gains a per-backend `effortTiers` list (§4.4).

### 4.2 Doctor button + results area (the bigger half)
- **Button + result** — insert in the "翻译后端" StackPanel right after `LblAuth` (`SettingsWindow.xaml:79`) or after `RowTimeout` (xaml:135-142): `<Button x:Name="BtnDoctor" Content="诊断" Click="BtnDoctor_Click"/>` (style after `BtnSave` xaml:188) + a results surface — a `<TextBox IsReadOnly="True" TextWrapping="Wrap"/>` or `<TextBlock x:Name="LblDoctorResult" Style="{StaticResource Hint}"/>`. Window is fixed-size inside a `ScrollViewer` (xaml:4-5,46) so added rows scroll safely.
- **Handler** — add `private async void BtnDoctor_Click(...)` near `BtnSave_Click` (xaml.cs:153). It must:
  1. `FlushBackendFields(_currentBackendId)` first (xaml.cs:113) so the probe sees the user's **unsaved** Command/Model/Reasoning/ApiKey (ApiKey is read from `TxtApiKey.Password`, xaml.cs:123 — and **must never be logged into the results area**, per the privacy promise at xaml:178-179).
  2. Build a registry and run the probe **async, off the UI thread, bounded by `TimeoutSec`**. SettingsWindow today holds only `ConfigService _svc` (xaml.cs:15) — **inject/construct a `TranslatorRegistry`** (or a new `DoctorService`) via `TranslatorRegistry.Build(_config).Get(id)`.
  3. Bind `AuthState.Level` / probe result to the lamp text+color and dump structured details (binary path, version, auth state, model-source note) into the results area.

### 4.3 Doctor service structure (Core, Law-6 compliant)
A `IBackendDoctor` (or a method on `ITranslator`) implemented **once generically**, reading the manifest:

- **Connectivity/auth:** run the manifest-declared probe (§4.4 `probe` verb) non-interactively from the neutral sandbox CWD via the existing `ProcessRunner` with the `TimeoutSec` ceiling (`Math.Max(3000, TimeoutSec*1000)`, ProcessTranslator.cs:56). Parse exit + a manifest-declared success/auth signature. For backends without a probe verb (copilot/agy), fall back to `CheckAuthAsync` (PATH presence → Unknown) + the agy bounded-retry/log-diagnosis path (§3).
- **Model list:** report the **static `ModelCatalog`** (AppConfig.cs:18 / DefaultConfig.cs:37-45) and label it "app catalog (CLI cannot enumerate)". Do **not** attempt live listing in v1 (no CLI supports it; contradicts current spec).
- **Effort tiers:** report the manifest `effortTiers` for the backend + whether the app actually threads effort (only codex does today). Honest "wired vs inert" labeling.
- **Return type:** a structured `DoctorReport` record (per-check rows: name, status ∈ {ok, warning, fail, unknown}, detail) — mirrors codex's own `doctor --json` shape and renders cleanly. Add to `Models.cs` next to `AuthState`.

### 4.4 Config + manifest schema changes
- **Per-vendor effort storage:** `BackendConfig.Reasoning` (AppConfig.cs:68) **already stores the chosen tier** — no config schema bump needed for persistence. The *vocabulary* (allowed tiers per backend) is **not** in config and should NOT be (it's a contract, not user state) → declare it in the manifest.
- **Manifest (`spec/backends.json`) new field `effortTiers`** per backend, e.g. codex: `"effortTiers": ["low","medium","high","xhigh"]`, claude: `[]` or omitted (model-is-tier), copilot: `["none","low","medium","high","xhigh","max"]`, agy: omitted. Surface via `BackendDef` — either reuse `Defaults` (Dictionary<string,JsonElement>, BackendManifest.cs:68) as `defaults.effortTiers` or add a typed `List<string>? EffortTiers` to `BackendDef` (BackendManifest.cs:46-78). Typed is cleaner; `Defaults` avoids a schema bump.
- **Doctor verb (optional, for real auth probes):** a manifest `probe` block (e.g. `{ "args": ["auth","status","--json"], "successSignature": "loggedIn", "kind": "auth-local" }`) so the generic interpreter can build a non-translate probe per backend without per-vendor C#. claude/codex get real probes; copilot/agy get presence-only or `-p` opt-in.
- `BackendConfig.Extra` ([JsonExtensionData], AppConfig.cs:82-83) can carry a cached last-doctor-result without a schema bump if you want persistence, but a first-class field is cleaner — recommend **not persisting** doctor results (re-run on demand).

---

## 5. Proposed design (options + recommendation)

### Decision A — Source of the effort-tier list
- **A1. Hardcoded per-vendor in C#** — fast, but violates Law 6 (per-vendor branching) and the manifest-as-SSOT intent. ✗
- **A2. Manifest-declared `effortTiers` per backend** — generic interpreter reads it; UI binds the ComboBox to it; same list every platform. ✓
- **A3. Probed live from the CLI** — impossible: no CLI enumerates tiers, and codex doesn't even validate them client-side. ✗
- **Recommendation: A2.** Manifest-declared, ComboBox `IsEditable="True"` so unknown/future tiers still round-trip and conformance stays green.

### Decision B — Doctor execution model
- **B1. Synchronous/blocking** — simplest, but `ProcessRunner` can hang up to the `TimeoutSec` ceiling (agy hangs to exit 124) → freezes the WPF UI thread. ✗
- **B2. Async, off-UI-thread, bounded by `TimeoutSec`, with a spinner/disabled button** — matches existing `ProcessRunner` async + the neutral-CWD/stdin fences the codebase already relies on. ✓
- **Recommendation: B2**, plus the §3 bounded-retry specifically for agy.

### Decision C — Doctor depth (auth gate)
- **C1. Cheap local check** — claude `auth status --json`, codex `login status`, copilot/agy PATH-presence + cred-file. No billing, fast, but doesn't prove network/translation. ✓ (default)
- **C2. Opt-in live `-p` probe** — a tiny real translation reusing `LooksLikeAuthError`; true E2E but **spends a request** (copilot/claude billable) and can hang. Behind an explicit "深度检测" toggle only.
- **Recommendation: C1 default, C2 opt-in.** Label results honestly ("已登录(本地凭据;未做联网验证)" vs "联网验证通过").

### Decision D — Where results render
- **D1. Inline Hint text** under `LblAuth` — minimal, fits the static-lamp pattern (xaml.cs:171 refresh), but cramped for multi-line reports.
- **D2. Read-only multi-line TextBox / expander** in the backend card — room for per-check rows (binary/version/auth/model-source). ✓
- **Recommendation: D2** (read-only `TextBox`, never echo the API key), with the one-line lamp (`LblAuth`) kept as the at-a-glance summary that the doctor now drives live.

---

## 6. Spec / conformance / PARITY plan (shared behavior — Law 1/2/3)

**Spec (`/spec`, do this FIRST):**
- **§6 (Backends):** add the `effortTiers` concept to the manifest doc + (optionally) the `probe` verb; state the cross-vendor truth — claude tier = model alias, codex via `-c model_reasoning_effort`, copilot via `--effort` (not yet wired), agy via model-label. Keep the existing "no CLI can list models reliably" line and explicitly scope the doctor to **connectivity/auth + static catalog reporting**, NOT live model listing.
- **§9 (Settings):** specify the effort ComboBox (per-vendor tiers, editable) and the doctor button + results semantics (auth lamp now live; depth = local by default).
- **agy quirk:** document the keyring transient + the bounded-retry/no-false-AuthFail rule (also fixes the existing ProcessTranslator.cs:88-92 false-positive).

**Conformance (`/conformance`, BEFORE Windows code):**
- **Extend `config-defaults.json`** (currently asserts `backends.codex.reasoning == "low"`, line 12) — keep that; optionally add asserts for any new default tier fields if defaults change. Do NOT pin per-platform UI.
- **New vector — manifest effort tiers / doctor probe shape.** Today CLI argv building is asserted in the test harness (`Program.cs:139`), not a JSON vector. Add a `backend-requests`-style vector for: (a) the `effortTiers` list per backend, and (b) the `probe` argv per backend (e.g. claude → `["auth","status","--json"]`). This is the Law-2 forcing function so the same probe definition is green on every platform's runner.
- **agy classifier vector:** a vector (or harness case) asserting that a log containing "not logged into Antigravity" **followed by** a success marker does NOT classify as AuthFail (regression-locks the §3 fix).

**PARITY (`PARITY.md`) rows:**
- New row: **"Per-vendor effort-tier selector (§6/§9)"** → Win 🚧→✅ when its vector passes; macOS ⬜ (or ✅ if landed concurrently); Linux ⬜.
- New row: **"Backend doctor (live auth lamp + connectivity probe) (§9)"** → Win ⬜; note macOS already has `refreshAuthHint()` (partial) — likely ⚠️ until it runs the same probe. **Flag the existing parity gap:** the live auth lamp is macOS-ahead/Windows-behind; this feature is partly *closing* an existing drift, partly *new* behavior on both.
- Per Law 3, if Windows ships and macOS doesn't, record it explicitly (same MAJOR.MINOR must = same feature set, or PARITY documents the temporary gap with a tracked task).

---

## 7. Open decisions for the human (numbered, each with a recommended default)

1. **Scope model-listing in or out of v1?** No CLI can enumerate non-interactively; live listing contradicts the current spec doc. **Recommended default: OUT.** Doctor reports the static `ModelCatalog` labeled "app catalog (CLI cannot list)". Revisit only if you want to add an API-key-based REST path later.
2. **Effort selector: editable ComboBox vs strict enum?** Strict could drop valid future tiers and risk regressing config-defaults.json:12 / Program.cs:139. **Recommended default: editable ComboBox** (manifest-driven items + free-text fallback).
3. **Wire `--effort` for claude/copilot now, or only show the selector for codex?** The flag exists for both but is unwired; wiring it changes translation behavior + needs new conformance. **Recommended default: show the selector wherever the manifest declares `effortTiers`, but for v1 only codex is actually threaded** (claude tier stays = model alias; copilot `--effort` wiring is a follow-up with its own vector). Label inert selectors honestly.
4. **Doctor auth depth: local-only vs opt-in live probe?** **Recommended default: local-only by default** (claude `auth status --json`, codex `login status`, copilot/agy presence+cred-file), with an explicit "深度检测" toggle for a billable `-p` E2E probe.
5. **agy doctor handling: bounded-retry-report-final vs simple presence?** **Recommended default: bounded retry (2–3×, >1s backoff) that reports the final state** + signature classification + keep the two Windows quirks distinct. Also fix the ProcessTranslator.cs:88-92 false-AuthFail regardless.
6. **Manifest field shape for tiers: typed `EffortTiers` vs `defaults.effortTiers`?** **Recommended default: typed `List<string>? EffortTiers` on `BackendDef`** (clearer, self-documenting) — accept the small schema touch; reuse `Defaults` only if you want zero schema change.
7. **Persist last doctor result?** **Recommended default: NO** — run on demand, render transiently; avoids stale state and keeps secrets out of config.
8. **Land macOS in lockstep or accept a tracked PARITY gap?** Same MAJOR.MINOR ⇒ same feature set (Law 3). **Recommended default: land the effort selector cross-platform together** (it's cheap and macOS already surfaces reasoning); accept a **tracked** PARITY gap for the doctor if macOS can't ship its probe simultaneously, with the row marked ⚠️ + a task.

---

## 8. Risks & unknowns

- **Law 6 (no per-vendor hardcode):** the strong temptation is `switch(id)`. The existing `isCodex` visibility flag (xaml.cs:93) is already a violation to *remove*, not extend. Doctor + tiers must be manifest-driven through the generic interpreter. **Risk: medium, mitigable.**
- **Law 1/3 (spec-first + parity):** both features are user-visible shared behavior. Shipping Windows-only without spec/conformance/macOS silently breaks parity. **Risk: high if skipped.**
- **Fake auth lamp today:** `CheckAuthAsync` for CLI only checks PATH (ProcessTranslator.cs:105-111); a doctor relying on it reports "installed" even when unauthenticated. Real auth needs an actual probe → slower, may hang on TTY-expecting CLIs (the very Windows quirks the codebase fences with stdin-pipe + neutral CWD + timeout ceiling). Must run async off the UI thread.
- **agy probe reliability (LOW-confidence area):** verify could NOT reproduce a clean exit-0 from agy — it **hung at exit 124** with empty output, and the `-p` log was zero bytes. So the manifest's `logDiagnosis="exit0+empty-stdout+auth-error-in-log"` rule may rarely see "exit0"; the doctor must treat hang/empty as best-effort and verify auth via cred-file/log success markers. The keyring `keyring.go:89` / ~1s constant / issue numbers are **external, unverified from this repo**.
- **codex doctor `overallStatus=warning` on this machine** (npm-root noise) — a naive parser would mis-flag healthy auth as failure. Parse specific check rows, not the top-level status.
- **No `TranslatorRegistry` in SettingsWindow today** (only `ConfigService`, xaml.cs:15) — must inject one; and probes must run against **flushed** in-memory config or they test stale values.
- **Secret handling:** HTTP doctor reads `TxtApiKey.Password` (xaml.cs:123); the results area must never echo the key (privacy promise, xaml:178-179).
- **Copilot `--allow-all-tools` gap:** documented as REQUIRED for non-interactive `-p`; absent from manifest args (backends.json:29) and plausibly the cause of the Win `-p` no-output bug #1181. Any copilot live probe should add it. **Unknown:** whether adding it fixes #1181 on this machine (not tested — would spend a request).
- **Effort tier names for codex/claude are routing-table-sourced, not CLI-confirmed** (codex doesn't validate client-side); treat the lists as advisory, editable, server-validated at request time.

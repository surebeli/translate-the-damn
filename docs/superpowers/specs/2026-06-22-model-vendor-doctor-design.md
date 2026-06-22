# Model-management: per-vendor effort selector + backend doctor — Design (2026-06-22)

Approved-direction design for the feature requested 2026-06-22. Builds on the research report
`.hopper/RESEARCH-model-vendor-doctor-2026-06-22.md`. Amends the main spec (`2026-06-17-…-design.md`)
§6 (backends) + §9 (settings). Shared behavior → spec-first (Law 1), vector-gated (Law 2),
parity-tracked (Law 3), manifest-driven (Law 6 — **no `switch(id)`**).

## Approved decisions (user, 2026-06-22)

- **Q1 — effort wiring:** wire `claude` + `copilot` `--effort` **too** (not just codex). Selector shows
  wherever the manifest declares `effortTiers`; agy has no effort flag → no selector.
- **Q2 — doctor depth:** local credential check by default; explicit **"深度检测"** opt-in for a
  billable `-p` live probe. Results labeled honestly (本地凭据 vs 联网验证).
- **Q3 — parity:** land the **effort selector cross-platform together**; the **doctor** may land
  Windows-first with a **tracked PARITY gap** for macOS (⚠️ + task) if it can't ship simultaneously.
- **Q4 — defaults:** model-listing **OUT** of v1 (no CLI enumerates; doctor reports the static
  `ModelCatalog`, labeled); effort = **editable** ComboBox (unknown/future tiers round-trip); agy =
  **bounded retry reporting final state** + signature classification; manifest tier field = **typed
  `List<string>? EffortTiers`**; doctor results **not persisted**; **fix** the `ProcessTranslator`
  false-`AuthFail` bug + regression vector.

## Manifest (`spec/backends.json`) changes

1. **`effortTiers` (typed `List<string>?` on `BackendDef`)** per backend:
   - `claude`: `["low","medium","high","xhigh","max"]`
   - `codex`: `["low","medium","high","xhigh"]`
   - `copilot`: `["none","low","medium","high","xhigh","max"]`
   - `agy`: omitted (effort is a model-label suffix, no flag) → no selector.
2. **Conditional `argsAppend`** (new generic interpreter construct) for the optional `--effort` flag:
   ```json
   "argsAppend": [ { "when": "reasoning", "args": ["--effort", "{reasoning}"] } ]
   ```
   on `claude` + `copilot`. Semantics: append the substituted `args` **only if** `vars[when]` is
   non-empty. claude/copilot get **no** `reasoning` default → out-of-the-box behavior is unchanged
   (no `--effort` passed); the user opts in by picking a tier. **codex is left as-is** (inline
   always-on `model_reasoning_effort="{reasoning}"`, default `low`) so its existing argv assertion
   (`Program.cs:139`) stays green.
3. **`probe` verb** (new, for the doctor) per backend — a non-interactive auth/connectivity probe the
   generic doctor runs:
   ```json
   "probe": {
     "args": ["auth","status","--json"],
     "network": false,
     "successSignatures": ["\"loggedin\":true"],
     "failSignatures": ["\"loggedin\":false"],
     "retries": 1
   }
   ```
   - `claude`: `args ["auth","status","--json"]`, success `"loggedin":true`, fail `"loggedin":false`, network false.
   - `codex`: `args ["login","status"]`, success `logged in`, fail `not logged in`, network false. (Do **not** gate on `codex doctor` top-level `overallStatus` — it is `warning` from npm-root noise; parse the auth signature.)
   - `copilot`: **no probe** → doctor reports "installed; auth not checkable non-interactively (深度检测 for live)".
   - `agy`: `retries: 3`, success log markers `["authenticated via keyring","authenticated successfully as","cloudcode-pa"]`, fail `["not logged into antigravity"]` **only when no later success** (see bug fix); doctor also checks cred files `%USERPROFILE%\.gemini\oauth_creds.json` + `google_accounts.json`. Bounded-retry + final-state reporting is generic (driven by `probe.retries`), not agy-specific C#.
   - Optional **deep** probe (Q2 opt-in): reuse the real translate path (`-p`) + `LooksLikeAuthError`; billable; behind the UI toggle only.

Probe success rule (generic): normalize stdout+stderr(+log) to lowercase/whitespace-stripped; **fail**
if any `failSignatures` present AND no `successSignatures` present; **ok** if any `successSignatures`
present (or `exitZeroIsAuth` + exit 0); else **unknown**. Bounded retry: run up to `retries+1` times
with >1s backoff; ok if any attempt ok; **degraded** (surfaced, not dropped) if an early attempt
failed but a later passed; **fail** only if all fail.

## Core changes (`platforms/windows/src/TranslateTheDamn.Core`)

- **`BackendManifest.cs`:** add `List<string>? EffortTiers` and `ProbeDef? Probe` to `BackendDef`;
  new `ProbeDef { List<string>? Args; bool Network; List<string>? SuccessSignatures;
  List<string>? FailSignatures; int Retries; bool ExitZeroIsAuth; }`; new
  `List<ArgsAppend>? ArgsAppend` where `ArgsAppend { string When; List<string> Args; }`.
- **`ManifestCliBackend.BuildInvocation`:** after building base args, append each `ArgsAppend` group
  whose `vars[when]` is non-empty (substituted). Generic; no per-vendor branch.
- **`DoctorService` (new):** `Task<DoctorReport> RunAsync(string backendId, AppConfig cfg, bool deep, CancellationToken)`.
  Reads the manifest `probe`; runs it via the existing `ProcessRunner` from the neutral sandbox CWD,
  bounded by `Math.Max(3000, TimeoutSec*1000)`; applies the generic success/retry rule; reports
  per-check rows (binary found+path, version, auth state, model-source note = static catalog, effort
  tiers + wired/inert). HTTP backends (google-v2/doubao) are out of scope here (excluded by the user).
- **`Models.cs`:** add `DoctorReport` (record: backendId, overall ∈ {ok,degraded,fail,unknown},
  rows: list of {name, status, detail}) next to `AuthState`. **Never** carry the API key in any row.
- **Bug fix `ProcessTranslator.cs:79-92`:** `LooksLikeAuthError` must not fire when the blob contains
  a `failSignature` that is **followed by** a `successSignature` (the agy keyring transient). Encode
  as: AuthFail only if a fail marker present AND no success marker present. Regression-locked by a
  conformance/harness case.

## App changes (`platforms/windows/src/TranslateTheDamn.App/UI/SettingsWindow`)

- **Effort ComboBox:** `RowReasoning` `TxtReasoning` `TextBox` → `CmbReasoning` editable `ComboBox`
  (mirror `CmbModel`). Load: populate items from the backend's manifest `effortTiers`, set
  `.Text = bc.Reasoning ?? <none>`. Flush: `bc.Reasoning = NullIfEmpty(CmbReasoning.Text)`.
  **Visibility:** driven by "manifest declares non-empty `effortTiers`" (delete the `isCodex`
  hardcode at `xaml.cs:93` — a Law-6 smell).
- **Doctor:** `BtnDoctor` ("诊断") + `ChkDeep` ("深度检测") + a read-only multi-line results
  `TextBox` (scrolls inside the existing `ScrollViewer`; never echoes `TxtApiKey.Password`). Handler
  `async void BtnDoctor_Click`: `FlushBackendFields` first (probe sees unsaved values), construct a
  `DoctorService` (inject `TranslatorRegistry.Build(_config)` / `ProcessRunner`), run off the UI
  thread, bind the result to the live auth lamp (`LblAuth`) + the results area.
- Settings stays single-instance + masked key (already shipped this session).

## macOS (Q3 — effort selector cross-platform)

Mirror the effort selector in the macOS settings (Swift) against the same shared manifest `effortTiers`
(macOS already surfaces reasoning). Written here but **not buildable on this Windows box** → verified
by macOS CI (`swift test` over the shared `conformance/`) + a future macOS UI walkthrough. The
**doctor** is Windows-first with a tracked PARITY ⚠️ for macOS.

## Spec / conformance / PARITY

- **Spec §6:** document `effortTiers`, the conditional `argsAppend`/`--effort` wiring (claude/copilot
  optional, codex inline), the `probe` verb, and that the doctor is scoped to connectivity/auth +
  static-catalog reporting (NOT live model listing). **Spec §9:** the effort ComboBox + doctor
  button/results + live auth lamp + depth toggle (local default).
- **Conformance (before Win code):**
  - extend `backend-requests`-style coverage / harness to assert per-backend `effortTiers` and the
    **`--effort` argv** that claude/copilot emit when `reasoning` is set (and **not** when empty);
  - new vector for the per-backend **probe argv** + success/fail signatures;
  - **agy classifier regression:** a blob with `not logged into antigravity` **followed by** a
    success marker must classify **ok/degraded, not AuthFail**.
- **PARITY rows:** "Per-vendor effort-tier selector (§6/§9)" Win ✅ + macOS ✅ (lockstep) / Linux ⬜;
  "Backend doctor (live auth lamp + probe) (§9)" Win ✅ / macOS ⚠️ (tracked) / Linux ⬜.

## Verification + three-party review

TDD: vectors RED → Core GREEN → App build → walkthrough. Then a **three-party adversarial review**
(codex + ≥2 independent verifier lenses) over the full diff — Law-6 compliance, per-vendor effort
argv, doctor async/timeout/secret-handling, agy retry + bug fix vs the regression vector,
spec/vector/PARITY consistency — P0/P1 fixed test-first and re-reviewed.

## Open risks

- Effort tier names for codex/claude are routing-table-sourced, not CLI-validated (editable ComboBox
  + server-side validation mitigates).
- Copilot `-p` no-output bug (#1181) + missing `--allow-all-tools` — the **deep** probe may need
  `--allow-all-tools`; untested (would spend a request). Local probe unaffected.
- agy probe reliability is low-confidence (it hung at exit 124 here) → doctor treats hang/empty as
  best-effort and leans on cred-file/log markers.
- macOS effort selector written blind (no Swift build here) → relies on macOS CI + later walkthrough.

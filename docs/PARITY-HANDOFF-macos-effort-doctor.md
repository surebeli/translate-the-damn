# Parity handoff — macOS: per-vendor effort selector + backend doctor

> Forward brief for a **macOS** session. Windows landed two features and **updated the shared
> contracts** (manifest + spec + conformance vectors). macOS is now behind. Your job: make macOS
> **match the already-updated vectors** and mirror the UI — do NOT edit the vectors/spec/manifest
> (they are the shared truth; changing them just pushes drift back onto Windows).

Design + research: `docs/superpowers/specs/2026-06-22-model-vendor-doctor-design.md`,
`.hopper/RESEARCH-model-vendor-doctor-2026-06-22.md`. Decisions (approved): wire claude+copilot
`--effort`; doctor local-default + opt-in deep `-p`; **effort selector lands cross-platform**, doctor
may be Win-first with a tracked gap.

## 0. Orient (read-only)

```bash
git pull
python3 scripts/parity-drift.py          # macOS now behind on the two new rows
swift test                                 # RED on the new vectors (effort-tiers, doctor-probe, doctor-classify)
```

The shared contracts already on `main` (do NOT change):
- **spec/backends.json** — each CLI backend gained `effortTiers`, a conditional `argsAppend`
  (`[{when, args}]`, appended only when the `when` var is non-empty), and a `probe` verb. codex effort
  stays inline (`model_reasoning_effort`); claude/copilot append `--effort {reasoning}` only when set;
  agy has none.
- **conformance/effort-tiers.json** — per-backend tier lists.
- **conformance/doctor-probe.json** — per-backend probe argv/kind/network.
- **conformance/doctor-classify.json** — the `ProbeClassifier` success-wins rule + the **agy
  keyring-transient regression** ("not logged into Antigravity" then a success marker ⇒ ok) + the
  codex "not logged in" ⊄ "logged in using" trap.
- **spec §6 / §9** — the effort tiers, argsAppend wiring, probe verb, doctor scope, depth.

## 1. Logic (Core, Swift) — gated by the vectors (Law 2 = must go green)

Mirror the Windows reference:
- **Manifest model** (mirror `platforms/windows/.../Manifest/BackendManifest.cs`): add `effortTiers:
  [String]?`, `argsAppend: [ArgsAppendDef]?` (`{when, args}`), `probe: ProbeDef?`
  (`args, kind, network, retries, exitZeroIsAuth, successSignatures, failSignatures, credFiles`).
- **Interpreter** (mirror `ManifestCliBackend.BuildInvocation`): after base args, append each
  `argsAppend` group whose `when` var is non-empty. Generic — no per-vendor branch. → makes the
  Windows-equivalent argv assertions / `effort-tiers` green.
- **ProbeClassifier** (mirror `platforms/windows/.../Backends/ProbeClassifier.cs`): normalize
  (lowercase + strip ALL whitespace) text + signatures; **ok if any successSignature; else fail if any
  failSignature; else unknown**. → makes `doctor-classify` green.
- **ProcessTranslator bug fix** (mirror the success-wins guard): in the macOS CLI translator's
  classify, skip AuthFail when an `AuthSuccessSignature` (manifest `probe.successSignatures`) is
  present — fixes the agy keyring false-AuthFail. The `doctor-classify` agy regression case locks it.

Wire the three vectors into the macOS Swift conformance runner (it already walks `conformance/`).

## 2. UI (App, SwiftUI) — per spec §6/§9, per-platform check (no vector)

- **Effort selector** (the cross-platform half): the per-backend "推理强度"/reasoning field →
  an editable picker bound to the manifest `effortTiers`; shown only when the manifest declares
  tiers (NOT a hardcoded id check — Law 6). Persist in `config.backends.<id>.reasoning`. macOS already
  surfaces reasoning, so this is mostly a control swap + manifest binding.
- **Doctor** (Windows-first; macOS tracked): a 诊断 button + read-only results + 深度检测 toggle +
  a live auth lamp, backed by a generic `DoctorService` (mirror
  `platforms/windows/.../Backends/DoctorService.cs`): binary presence; local probe (claude/codex
  argv with bounded retry; agy cred-file; copilot presence-only); opt-in deep `-p`; reports the static
  model catalog + effort tiers. **Never surface the API key or any raw stdout/stderr/exception —
  status-only details** (this was the heaviest review finding on Windows; codex flagged 3 separate
  leak paths). Probe must run off the main thread, bounded, and be cancelable on window close.

## 3. Verify + record (definition of done)

1. `swift test` → the three new vectors green (Law-2 truth).
2. UI walkthrough: effort picker shows the right tiers per backend (claude `low…max`, codex
   `low…xhigh`, copilot `none…max`, agy none); 诊断 reports auth/model-source/effort; agy keyring
   transient does NOT show as failure; the key never appears in results.
3. Flip `PARITY.md`: **Per-vendor effort-tier selector** macOS → ✅; **Backend doctor** macOS → ✅ (or
   ⚠️ if only partially landed). Re-run `python3 scripts/parity-drift.py`.

## Reference (Windows implementation to mirror)
- Manifest types: `platforms/windows/src/TranslateTheDamn.Core/Backends/Manifest/BackendManifest.cs`
- Interpreter argsAppend: `.../Manifest/ManifestCliBackend.cs`
- Classifier: `.../Backends/ProbeClassifier.cs`  ·  bug fix: `.../Backends/ProcessTranslator.cs`
- Doctor: `.../Backends/DoctorService.cs`  ·  UI: `.../App/UI/SettingsWindow.xaml(.cs)`

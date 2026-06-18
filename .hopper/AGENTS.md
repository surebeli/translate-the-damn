# translate-the-damn macOS port — Agent Instances (v2.0 task-based binding)

Direction: macOS native port (Swift / SwiftUI + AppKit). The **main session is CEO/CTO** (decompose, dispatch, cross-review, record). Dev + review work is delegated to hopper vendors + Claude Code subagents.

## Active channels

| Channel | Vendor | Model (verified live 2026-06-18) | Reasoning | Role |
|---|---|---|---|---|
| main-session | — (Claude Code) | — | — | CEO/CTO: orchestrate, decompose, cross-review, record; in-session high-context work (conformance runner, acceptance, parity) |
| subagent | — (Claude Code Agent tool) | — | — | Parallel exploration, reference-reading (Windows Core), targeted impl/review with full main-session context |
| opencode | opencode | `tokenbox/deepseek-v4-pro` | N/A — opencode ignores `--reasoning` (deepseek-v4-pro reasoning is intrinsic) | Hard logic: manifest interpreter, hotkey, pipeline, popup, composition; spec-write; spec-blindspot-hunt |
| mimo | mimo | `xiaomi/mimo-v2.5-pro` | `--reasoning xhigh` → mimo `--variant max` | Adversarial review (review-tier gets the extended timeout floor); small/reasoning code-impl. **AVOID bulk code-impl** (>180s timeout — see plugin `ISSUE-mimo-codeimpl-timeout.md`) |
| kimi | kimi | default `kimi-code/kimi-for-coding` (no `-m`) | config-driven (no CLI flag) | Bulk code-impl: scaffold, boilerplate, mechanical edits, sidecar-polish |

## Task-type → default channel

| Task-type | Default channel | Why |
|---|---|---|
| `spec-write` | opencode | High reasoning |
| `code-impl` (bulk / scaffold) | kimi | Cheap tier, static default code-impl |
| `code-impl` (hard logic) | opencode | deepseek-v4-pro reasoning |
| `code-review-adversarial` | mimo | Review-tier timeout floor; `--variant max`; DIFFERENT channel than builder |
| `code-review-acceptance` | subagent | Needs full main-session context + manual flow |
| `sidecar-polish` | kimi / subagent | Cheap hygiene |
| `spec-blindspot-hunt` | opencode | High reasoning for unknown-unknowns |

## Cross-review protocol (Constitution Law 2 + user directive)

1. Every dev task is reviewed by a **different channel** than its builder before `done`.
2. Review findings → fix task (original builder or another) → **re-review by a second reviewer** for any P0/P1 fix.
3. **Hard gate**: a logic task is `done` only when its `conformance/` vector passes in the Swift runner. UI tasks verified vs spec §3-9 + manual check.
4. **Spec-first** (Constitution Law 1): any behaviour change → edit `/spec` + `/conformance` first, then platform code.

## Routing rules

- No self-review: mimo never reviews mimo-built code; opencode never reviews opencode-built code. Builders are kimi + opencode; adversarial reviewer is mimo; acceptance/parity is subagent.
- If a vendor times out / fails (e.g. mimo >180s on code-impl), reassign to another channel and log it in `COST-LOG.md` + file/append a hopper `ISSUE-*.md`.
- Row-level `Vendor` column in `queue.md` overrides the default.

## Reassignment

Edit this file + `.hopper/MANIFEST.md` together. If a vendor proves unsuitable for this port, mark it `deferred` and reroute.

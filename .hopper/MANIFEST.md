# MANIFEST — translate-the-damn macOS port

Anchor: `.hopper/MANIFEST.md::root`

The macOS (Swift) port of translate-the-damn, orchestrated from the main session (CEO/CTO) via hopper vendors + subagents. Native per Constitution line 7 (macOS = Swift); behaviour parity with Windows is enforced by `conformance/` vectors + `PARITY.md`, NOT by shared code.

## Current phase

**Phase**: M0 (scaffold + charter) — in progress 2026-06-18.

**Status**: Research complete; contracts digested (design spec, `spec/backends.json`, 6 conformance vectors, `strings/zh-CN.json`, PARITY). hopper shim repointed to 0.12.0; `.hopper/` scaffolded (queue v2, AGENTS, MANIFEST, 6 task frames, COST-LOG); stale-binary issue filed; `platforms/macos/CLAUDE.md` created; `docs/PORTING-macos.md` Avalonia→Swift drift fixed. **Paid vendor dispatch HELD pending user review of `.hopper/queue.md`.**

**Next**: M1 (Swift conformance runner) via subagent — the green gate. Then M2 core logic dispatched to opencode + kimi, adversarially reviewed by mimo.

## Source of truth

- Laws / pointer map: root `CONSTITUTION.md`
- Behaviour spec: `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md`
- Backend manifest: `spec/backends.json` (interpreter must read this, not hardcode)
- Conformance vectors (done gate): `conformance/*.json`
- Strings: `strings/zh-CN.json`
- Parity board: `PARITY.md` (macOS column ⬜→✅ per feature)
- Porting delta: `docs/PORTING-macos.md`
- Windows reference impl: `platforms/windows/src/`
- Orchestration: `.hopper/queue.md` (tasks), `.hopper/AGENTS.md` (channels + routing), `.hopper/COST-LOG.md` (usage), `.hopper/ISSUE-*.md` (hopper bugs)

## 修改记录

| 日期 | Cursor 变化 | 由 |
|------|------------|---|
| 2026-06-18 | Repo read; contracts digested; hopper vendors verified (opencode/mimo/kimi READY in 0.12.0); stale-binary issue filed + shim repointed; `.hopper/` scaffolded (queue v2, AGENTS, MANIFEST, task frames, COST-LOG); `platforms/macos/CLAUDE.md` created; PORTING-macos drift fixed. M0 in progress. | main session (CEO/CTO) |

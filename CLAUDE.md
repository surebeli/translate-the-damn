# CLAUDE.md

This repository is governed by **[CONSTITUTION.md](./CONSTITUTION.md)** — **read it first.**

It defines the inviolable laws (spec-first, shared conformance vectors must pass on every
platform, same `MAJOR.MINOR` = same feature set across platforms) and is the **pointer map** to
every shared artifact: the design spec, the declarative backend manifest (`spec/backends.json`),
the language-neutral conformance vectors (`conformance/`), shared strings (`strings/`), the
parity matrix (`PARITY.md`), the versioning rules, and the PR checklist.

Native per platform, no shared UI/runtime code; consistency is enforced by shared contracts +
conformance vectors + the parity matrix, not by sharing binaries.

Per-platform notes live in each platform's local `CLAUDE.md`. **Windows** currently lives at
`src/` (Core + App) and `tests/`; macOS/Linux land under `platforms/<os>/` when added.

Before changing behavior anywhere: update `/spec` and/or `/conformance` first (Constitution Law 1).

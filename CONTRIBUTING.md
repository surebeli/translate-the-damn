# Contributing to translate-the-damn

Thanks for helping out. This project is **native per platform, one shared contract** — Windows
(C#/WPF) and macOS (Swift/SwiftUI) ship the *same behaviour* without sharing UI or runtime code.
That is only possible because the repo is governed by a small set of inviolable rules. **Read them
before you touch anything.**

## 0. Read these first

1. **[CONSTITUTION.md](./CONSTITUTION.md)** — the single entry point and pointer map. It defines the
   Laws and points at every shared artifact. If you read nothing else, read this.
2. **[PARITY.md](./PARITY.md)** — the feature × platform board (who owes what).
3. The design spec — `docs/superpowers/specs/2026-06-17-translate-the-damn-design.md` (the single
   source of truth for behaviour; section numbers like §5, §6, §8 are referenced throughout).
4. **[docs/CROSS-PLATFORM-PARITY.md](./docs/CROSS-PLATFORM-PARITY.md)** — how drift is surfaced and
   how to align a feature across platforms.
5. Per-platform notes: `platforms/windows/CLAUDE.md`, `platforms/macos/CLAUDE.md`.

## 1. The Laws you must not break

These come from `CONSTITUTION.md`. They are not style preferences — CI enforces most of them.

1. **Spec-first.** Any change to *behaviour or logic* changes `/spec` and/or `conformance/`
   **first**, then platform code. Never the other way around.
2. **Conformance vectors are the only source of truth for shared logic.** The language-neutral JSON
   in `conformance/` defines expected behaviour; each platform proves it with a *native* runner over
   the *same* JSON. Changing a behaviour means changing the vector, which turns every platform's CI
   red until each one matches.
3. **Same `MAJOR.MINOR` = same feature set on every platform.** If a platform hasn't caught up it
   stays on the lower version; the gap is recorded in `PARITY.md`. A version number must never mean
   different things on different platforms.
4. **The `config.json` schema is sacred.** Only an *incompatible* data-format change bumps its
   `version` field, and it bumps on all platforms at once. It is independent of the app version.
5. **Consistency boundary.** *Must be identical:* feature / behaviour / timing / state machine /
   user-facing text / config format / backend invocation. *Must be natively each platform's own:*
   visual material (Acrylic vs `NSVisualEffectView`), system integration (tray, hotkey, clipboard,
   permissions), control styling. One sentence: **"same behaviour, each platform's own skin."**
6. **Backends are data first.** New or changed backends edit `spec/backends.json` (the declarative
   manifest) — not just platform code. Only logic the manifest genuinely cannot express gets a
   native per-platform hook, recorded in `PARITY.md`.

## 2. The contribution loop

A single change flows like this (Constitution §4):

1. **Land it in the shared layer first** — edit the design spec, `spec/backends.json`,
   the relevant `conformance/` vector(s), and/or `strings/` as needed.
2. **Implement it on your platform** until its conformance vectors pass locally (see §4).
3. **Update `PARITY.md`** — mark the feature ✅ on your platform and ⬜ on the platforms that now owe
   it. (This is machine-enforced; see §5.)
4. **Open a PR.** As soon as it merges, the other platforms' CI goes red against the new vector —
   their work is now visible on the board. You still only ever work on one platform at a time; the
   *tests and the matrix* track what's outstanding, not your memory.

If you can only do one platform, that's fine — leave the others ⬜ in `PARITY.md` and the forcing
function will surface the remaining work.

## 3. Building & running each platform

### Windows 11 — C# / .NET 9, WPF

Requires the .NET 9 Desktop SDK/runtime.

```powershell
dotnet build platforms\windows\TranslateTheDamn.sln -c Release
.\platforms\windows\src\TranslateTheDamn.App\bin\Release\net9.0-windows\TranslateTheDamn.exe
```

The solution is dependency-free (framework-only: WPF + WinForms tray + JSON/HTTP + Win32 P/Invoke).

### macOS — Swift / SwiftUI, Apple Silicon (arm64), macOS 14+

Requires Xcode 16 / Swift 6 command-line tools.

```bash
./platforms/macos/scripts/build-app.sh        # -> platforms/macos/TranslateTheDamn.app
open platforms/macos/TranslateTheDamn.app
```

For distribution, sign + notarize with `platforms/macos/scripts/sign-notarize.sh`.

> **The macOS app must NOT be sandboxed.** It spawns the user's agent CLIs (`claude`, `codex`, …),
> which the App Sandbox would block. Do not add an `App Sandbox` entitlement.

Neither app has a main window — look for the tray / menu-bar icon (green = listening, grey = paused);
click it for Settings.

### Linux

Not a current target — translate-the-damn ships on Windows + macOS only. (Local-model support is the
next roadmap item; see the README.)

## 4. Tests = the conformance vectors

A logic change is **done** only when its `conformance/` vector passes via your platform's native
runner. The vectors live in `conformance/*.json` (format documented in `conformance/README.md`):
`prompt-builder`, `ansi-stripper`, `hotkey-parser`, `config-defaults`, `backend-requests`,
`pipeline-cache`, `popup-sizing`, `effort-tiers`, `doctor-probe`, `doctor-classify`,
`credential-discovery`, plus the `spec/backends.json` manifest the backend cases exercise.

Run them locally:

```powershell
# Windows — offline conformance + unit suite (dependency-free; no network, no spawned CLIs)
dotnet run --project platforms\windows\tests\TranslateTheDamn.Tests
```

```bash
# macOS — conformance + unit suite
( cd platforms/macos && swift test )

# Cross-platform drift report (Python stdlib, no deps)
python3 scripts/parity-drift.py
```

**Add the vector before the logic.** If you're introducing new shared behaviour, write/extend the
vector in `conformance/` first so every platform has a concrete test to satisfy.

## 5. CI gates (`.github/workflows/conformance.yml`)

Every push and PR runs:

- **`conformance — macOS (swift)`** — `swift test` over `conformance/`.
- **`conformance — Windows (dotnet)`** — `dotnet run --project platforms/windows/tests/...` over the
  *same* `conformance/`.
- **`parity-verify`** — cross-checks each platform's real vector results against its `PARITY.md`
  column, so a row can't claim ✅ that the vectors don't back up.
- **`parity drift (visibility)`** — surfaces `scripts/parity-drift.py` in the checks (visibility, not a
  hard gate) and runs **`parity-evidence`**, which requires every ✅ UI row to
  point at real source in `spec/ui-evidence.json`.
- **`PARITY coupling gate`** (PRs only) — **fails your PR if you changed `platforms/<os>/src/**`
  without editing `PARITY.md`.** Escape hatch for genuinely behaviour-neutral changes: add a commit
  message line `parity:n/a <reason>`.

Green CI is required to merge. If a vector regresses on a platform you didn't touch, that's the
Law 2 forcing function doing its job — the lagging platform owes the alignment.

## 6. Opening a pull request

- Branch from the default branch; don't push directly to it.
- Fill in the PR template (`.github/PULL_REQUEST_TEMPLATE.md`) — it is the spec-first checklist:
  spec/vectors updated first, `spec/backends.json` updated for backend changes, `strings/` updated
  for user-visible text, `config.json` `version` bumped only for incompatible schema changes,
  `PARITY.md` updated, vectors green, version bumped per spec §12 if releasing.
- Keep commits focused; describe *what behaviour changed* and *which platforms it touches*.
- A maintainer reviews against the Laws above. Expect to be asked to move a behaviour change into the
  spec/vectors first if it landed in platform code only.

## 7. Secrets & config — never commit

User configuration and secrets live **only** in the local `config.json`
(`~/.translatethedamn/config.json`, or `%USERPROFILE%\.translatethedamn\config.json` on Windows),
which is created on first run. The `apiKey` field and any other credential live there and **must
never be committed** — never copy your real `config.json` into the repo. `.gitignore` excludes the
secret filenames (`config.json`, `local.config.json`, `**/.translatethedamn/`, `*.bak`, `*.log`) as a
backstop, but the first line of defense is you: do not add real keys to fixtures, tests, vectors, or
docs. Conformance vectors use placeholder values only.

See `SECURITY.md` for how to report a vulnerability.

## 8. Code of Conduct

This project follows the [Contributor Covenant](./CODE_OF_CONDUCT.md). By participating you agree to
uphold it.

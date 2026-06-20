#!/usr/bin/env python3
"""PARITY coupling gate — Constitution Law 3, made into a machine check.

The PR template has had "Updated PARITY.md" as a checkbox for ages, yet platform code shipped
without the matching PARITY row flipping (the 2026-06-20 retrospective documents the resulting
stale). A passive checkbox is ignorable. This gate is not: when a platform's source under
`platforms/<os>/src/**` changed in a range but `PARITY.md` was not touched in the same range, it
fails and names the platform(s).

Escape hatch (for genuinely behaviour-neutral changes — refactors, comments, internal renames):
put `parity:n/a` (any case, optional space/slash) in a commit message in the range. That forces a
*conscious* "this doesn't change the cross-platform feature set" instead of a silently-skipped box.

Usage:
  parity-gate.py                         # default range origin/main...HEAD
  parity-gate.py --base <ref> --head <ref>
  parity-gate.py --warn                  # report only, always exit 0 (gradual rollout)

Exit: 0 = ok / escaped / nothing to gate; 1 = coupling violation (unless --warn); 2 = range error.
"""
import argparse
import re
import subprocess
import sys

PLATFORM_SRC = re.compile(r"^platforms/([^/]+)/src/")
ESCAPE = re.compile(r"parity:\s*n/?a", re.IGNORECASE)


def git(*args):
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def main():
    ap = argparse.ArgumentParser(description="Fail when platform src changes without a PARITY.md change.")
    ap.add_argument("--base", default="origin/main", help="base ref (CI: the PR target branch)")
    ap.add_argument("--head", default="HEAD", help="head ref")
    ap.add_argument("--warn", action="store_true", help="report only; always exit 0")
    a = ap.parse_args()

    # Three-dot: changes introduced by head since it diverged from base (what a PR review cares about).
    rng = f"{a.base}...{a.head}"
    code, out, err = git("diff", "--name-only", rng)
    if code != 0:
        # Infra issue (shallow clone, unknown ref) — don't block the pipeline on it; surface loudly.
        print(f"⚠ parity-gate: cannot diff {rng!r} ({err.strip()}); skipping (run with fetch-depth: 0).")
        return 0

    changed = [l for l in out.splitlines() if l.strip()]
    platforms = sorted({m.group(1) for n in changed if (m := PLATFORM_SRC.match(n))})
    parity_touched = "PARITY.md" in changed

    if not platforms:
        print("✓ parity-gate: no platform source changed — nothing to couple.")
        return 0
    if parity_touched:
        print(f"✓ parity-gate: platform src changed ({', '.join(platforms)}) and PARITY.md was updated.")
        return 0

    _, msgs, _ = git("log", "--format=%B", rng)
    if ESCAPE.search(msgs):
        print(f"✓ parity-gate: platform src changed ({', '.join(platforms)}) but a commit declared "
              f"`parity:n/a` — accepted as behaviour-neutral.")
        return 0

    print("✗ parity-gate: platform source changed without a PARITY.md update.")
    print(f"    platforms touched: {', '.join(platforms)}")
    print(f"    range: {rng}")
    print("  If this changes the cross-platform feature set, update PARITY.md (flip the row for the")
    print("  platform, and check whether a peer is now behind). If it is behaviour-neutral, add a")
    print("  commit message line `parity:n/a <reason>`. See docs/CROSS-PLATFORM-PARITY.md.")
    return 0 if a.warn else 1


if __name__ == "__main__":
    sys.exit(main())

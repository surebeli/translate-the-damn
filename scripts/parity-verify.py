#!/usr/bin/env python3
"""PARITY ⇄ vector truth cross-check — closes the blind spot #7 and #8 leave open.

The mechanism had three layers before this:
  #7 conformance CI — a vector that REGRESSES on platform P turns P's job red.
  #8 coupling gate  — changing platforms/<os>/src/** without touching PARITY.md fails the PR.
But one stale class still slipped through BOTH: a logic row whose vector is GREEN on platform P while
PARITY still marks that platform 🚧/⬜ (under-claim). #7 doesn't fire (the job is green); #8 doesn't
fire (PARITY may well have been edited — just the wrong cell). This is exactly the 72cea10 case
(`popup-sizing` green on Windows, row left 🚧) that the 2026-06-20 retrospective had to fix by hand.

This checker compares, for ONE platform, that platform's ACTUAL per-vector results (emitted by its own
conformance runner) against what PARITY.md declares for that platform's column — for every logic row:

  vector GREEN  but column not ✅   → UNDER-CLAIM  (the 72cea10 reverse-stale)
  column ✅      but vector RED      → OVER-CLAIM   (also caught by #7, reported here for completeness)
  column ✅      but vector ABSENT   → OVER-CLAIM   (claims a feature green that this platform never runs)

It runs INSIDE each platform's CI job (the only place that platform's vector truth is observable), so
no cross-platform artifact juggling. PARITY parsing is imported from parity-drift.py — single source,
so the two tools can never disagree about what a row means.

Results file shape (emitted by the runners):
  { "platform": "macos", "vectors": { "popup-sizing": true, "pipeline-cache": true, ... } }

Usage:
  parity-verify.py --platform macOS --results conformance-results.macos.json
  parity-verify.py --platform Win   --results conformance-results.windows.json --warn
Exit: 0 = consistent / --warn; 1 = mismatch; 2 = bad input.
"""
import argparse
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load_parity_drift():
    """Import parity-drift.py (hyphenated → importlib) so PARITY parsing has ONE source of truth."""
    path = HERE / "parity-drift.py"
    spec = importlib.util.spec_from_file_location("parity_drift", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def resolve_platform(declared, requested):
    """Match the --platform arg to a PARITY column name, case-insensitively, with common aliases."""
    aliases = {"windows": "win", "win": "win", "macos": "macos", "mac": "macos",
               "osx": "macos", "linux": "linux"}
    want = aliases.get(requested.lower(), requested.lower())
    for name in declared:
        if aliases.get(name.lower(), name.lower()) == want:
            return name
    return None


def main():
    ap = argparse.ArgumentParser(description="Cross-check PARITY's column for ONE platform against that platform's real vector results.")
    ap.add_argument("--platform", required=True, help="platform column to check (Win | macOS | Linux)")
    ap.add_argument("--results", required=True, help="path to that platform's emitted conformance-results JSON")
    ap.add_argument("--parity", default=str(HERE.parent / "PARITY.md"), help="path to PARITY.md")
    ap.add_argument("--warn", action="store_true", help="report only; always exit 0")
    a = ap.parse_args()

    try:
        results = json.loads(Path(a.results).read_text(encoding="utf-8"))
        vectors = results.get("vectors", {})
        if not isinstance(vectors, dict):
            raise ValueError("`vectors` must be an object of stem→bool")
    except Exception as e:  # noqa: BLE001 — surface any input problem as exit 2
        print(f"✗ parity-verify: cannot read results {a.results!r}: {e}")
        return 2

    pd = load_parity_drift()
    parsed = pd.parse_parity(Path(a.parity))
    col = resolve_platform(parsed["platforms"], a.platform)
    if col is None:
        print(f"✗ parity-verify: platform {a.platform!r} not a PARITY column ({parsed['platforms']}).")
        return 2

    under, over_red, over_absent, ok = [], [], [], []
    for f in parsed["features"]:
        if f["kind"] != "logic":
            continue  # UI/backend rows have no vector truth here — out of scope by design
        declared = f["status"].get(col)
        for stem in f["vectors"]:
            green = vectors.get(stem)  # True / False / None(=not run by this platform)
            row = f["feature"]
            if green is True and declared != pd.SHIPPED:
                under.append((row, stem, declared))
            elif declared == pd.SHIPPED and green is False:
                over_red.append((row, stem))
            elif declared == pd.SHIPPED and green is None:
                over_absent.append((row, stem))
            elif green is True and declared == pd.SHIPPED:
                ok.append((row, stem))

    g = pd.GLYPH
    print(f"parity-verify: platform={col}  results={a.results}")
    print(f"  vectors emitted: {len(vectors)}  ({sum(1 for v in vectors.values() if v)} green)")
    if ok:
        print(f"  ✓ {len(ok)} logic row(s) agree (vector green ⇄ column {g[pd.SHIPPED]}).")

    bad = under or over_red or over_absent
    for row, stem, decl in under:
        print(f"  ✗ UNDER-CLAIM: `{stem}` is GREEN on {col} but row is {g.get(decl,'?')} — flip it to {g[pd.SHIPPED]}.")
        print(f"       row: {row}")
    for row, stem in over_red:
        print(f"  ✗ OVER-CLAIM: row marked {g[pd.SHIPPED]} on {col} but `{stem}` is RED (also fails the conformance job).")
        print(f"       row: {row}")
    for row, stem in over_absent:
        print(f"  ✗ OVER-CLAIM: row marked {g[pd.SHIPPED]} on {col} but `{stem}` was NOT run by this platform's runner.")
        print(f"       row: {row}")

    if not bad:
        print(f"  ✓ PARITY {col} column is consistent with real vector results.")
        return 0
    print(f"\n  {len(under)} under-claim, {len(over_red)} over-claim(red), {len(over_absent)} over-claim(absent).")
    print("  Fix PARITY.md to match reality (or fix the impl). This is the 72cea10-class stale guard.")
    return 0 if a.warn else 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Evidence-pointer gate for UI rows — the part of PARITY that has no vector to verify.

parity-verify.py (#9) checks LOGIC rows against real vector results. But UI rows (acrylic blur,
focus-steal, tray, secure entry, ...) have no language-neutral vector, so nothing checked that a ✅
there was real — that's the residual blind spot #4 addresses.

This gate requires every ✅ in a UI-kind row to point at the source that implements it (in
spec/ui-evidence.json), per platform, and verifies each pointer resolves (file exists + optional
symbol present). So:

  ✅ but no evidence entry / dangling path / missing symbol → FAIL (a claim a reviewer can't confirm)
  evidence resolves but the row is NOT ✅ on that platform   → WARN (possible under-claim — a human
                                                               must confirm behaviour; a file existing
                                                               is not proof the feature works)

It does NOT prove behaviour (only spec + a human UI walkthrough can). It makes the claim auditable
from a diff and keeps the pointers themselves honest. PARITY parsing is imported from parity-drift.py
(single source). Runs in CI from any checkout (all platforms' src is in the repo).

Usage:
  parity-evidence.py                 # check all UI rows, all platforms
  parity-evidence.py --warn          # report only, exit 0
Exit: 0 = ok (warnings allowed) / --warn; 1 = a ✅ lacks resolvable evidence; 2 = bad input.
"""
import argparse
import importlib.util
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def load_parity_drift():
    spec = importlib.util.spec_from_file_location("parity_drift", HERE / "parity-drift.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def row_key_for(feature_text, evidence_keys):
    """Match a PARITY feature row to an evidence key by leading-substring (keys are kept short)."""
    for k in evidence_keys:
        if feature_text.startswith(k):
            return k
    return None


def resolve(pointer):
    """Return (ok, detail) for one {path, symbol?} pointer."""
    p = ROOT / pointer["path"]
    if not p.is_file():
        return False, f"missing file {pointer['path']}"
    sym = pointer.get("symbol")
    if sym:
        try:
            if sym not in p.read_text(encoding="utf-8", errors="replace"):
                return False, f"symbol {sym!r} not found in {pointer['path']}"
        except OSError as e:
            return False, f"cannot read {pointer['path']}: {e}"
    return True, pointer["path"] + (f" ∋ {sym}" if sym else "")


def main():
    ap = argparse.ArgumentParser(description="Require every ✅ UI row to have a resolvable source pointer.")
    ap.add_argument("--evidence", default=str(ROOT / "spec" / "ui-evidence.json"))
    ap.add_argument("--parity", default=str(ROOT / "PARITY.md"))
    ap.add_argument("--warn", action="store_true", help="report only; exit 0")
    a = ap.parse_args()

    try:
        ev = json.loads(Path(a.evidence).read_text(encoding="utf-8"))["evidence"]
    except Exception as e:  # noqa: BLE001
        print(f"✗ parity-evidence: cannot read {a.evidence!r}: {e}")
        return 2

    pd = load_parity_drift()
    parsed = pd.parse_parity(Path(a.parity))
    keys = list(ev.keys())

    fails, warns, ok = [], [], 0
    for f in parsed["features"]:
        if f["kind"] != "ui":
            continue  # logic/backend rows are covered by parity-verify / the manifest
        key = row_key_for(f["feature"], keys)
        entry = ev.get(key, {}) if key else {}
        for platform, status in f["status"].items():
            pointers = entry.get(platform, [])
            if status == pd.SHIPPED:
                if not pointers:
                    fails.append(f"✅ {platform} `{f['feature']}` — no evidence pointer in ui-evidence.json")
                    continue
                bad = [d for (good, d) in (resolve(p) for p in pointers) if not good]
                if bad:
                    for d in bad:
                        fails.append(f"✅ {platform} `{f['feature']}` — dangling evidence: {d}")
                else:
                    ok += 1
            elif pointers:
                # has evidence but not marked shipped → it resolves? then likely an under-claim.
                if all(good for (good, _) in (resolve(p) for p in pointers)):
                    warns.append(f"{pd.GLYPH.get(status,'?')} {platform} `{f['feature']}` — evidence resolves "
                                 f"but row not ✅ (possible under-claim; confirm behaviour, then flip).")

    print(f"parity-evidence: {ok} ✅ UI claim(s) backed by resolvable source; "
          f"{len(fails)} unbacked; {len(warns)} possible under-claim(s).")
    for w in warns:
        print(f"  ⚠ {w}")
    for x in fails:
        print(f"  ✗ {x}")
    if not fails:
        print("  ✓ every ✅ UI row points at source that exists.")
        return 0
    print("\n  A ✅ UI row must point at real source in spec/ui-evidence.json (so the claim is auditable).")
    return 0 if a.warn else 1


if __name__ == "__main__":
    sys.exit(main())

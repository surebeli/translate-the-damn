#!/usr/bin/env python3
"""parity-drift — one-command cross-platform alignment report.

Reads the shared contracts (Constitution pointer map) and reports, per platform, what is
*behind* the others — turning "run every platform's test suite to discover drift" into a single
local command.

BOUNDARY (read this): this tool reflects the **manually-maintained declarations in PARITY.md**
(the ✅/🚧/⬜ are typed by humans). It does NOT run any platform's tests and does NOT prove a
conformance vector actually passes. Per Constitution Law 2 the only *truth* is the vectors going
green on each platform's CI. So "DECLARED-ALIGNED" here means "the PARITY board is internally
consistent + versions/refs line up" — not "every platform's suite is green". Use it as the cheap
first signal; the CI vector runs remain the source of truth.

Sources of truth (repo root):
  PARITY.md                 feature × platform board (✅/🚧/⬜/⚠️/—) + Version table
  conformance/*.json        language-neutral logic vectors
  spec/backends.json        declarative backend manifest

What it flags:
  1. Feature drift  — a feature shipped (✅) on ≥1 platform but not ✅ on another applicable one.
  2. Law 3          — platforms that DECLARE the same MAJOR.MINOR but have different ✅ feature sets
                      ("same MAJOR.MINOR = same feature set" — the actual Law 3 assertion).
  3. Version/schema — platforms whose App MAJOR.MINOR or config schema differ.
  4. Conformance    — vector files on disk unreferenced by any feature row (orphans), and vectors
                      referenced in PARITY that don't exist on disk (dangling).
  5. Spec gaps      — features with no § reference (and, worse, shipped-but-no-spec → Law 1).
  6. Warnings       — unrecognized status cells / version table not parsed (parser didn't choke).

Each "behind" item carries a next-step action derived from its Conformance column kind
(logic → make the vector pass; backend → implement via the manifest; ui → spec + UI check).

Usage:
  python3 scripts/parity-drift.py                 # human report
  python3 scripts/parity-drift.py --json          # machine-readable JSON (has_drift/result/summary)
  python3 scripts/parity-drift.py --fail-on-drift # exit 1 on feature/Law3/version/schema/dangling drift
  python3 scripts/parity-drift.py --strict        # also gate on orphans + shipped-without-spec
  python3 scripts/parity-drift.py --root <path>   # override repo root (else auto-detected)

Zero dependencies (Python 3.8+ stdlib only).
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

# The report/digest contain CJK + emoji; Windows consoles often default to a non-UTF-8 code page
# (cp1252/gbk) which would raise UnicodeEncodeError. Force UTF-8 output where supported.
try:
    sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[attr-defined]
except Exception:
    pass

JSON_SCHEMA_VERSION = 1

# ── status vocabulary (PARITY.md legend) ──────────────────────────────────────
SHIPPED, WIP, TODO, PARTIAL, NA, UNKNOWN = "shipped", "wip", "todo", "partial", "na", "unknown"
GLYPH = {SHIPPED: "✅", WIP: "🚧", TODO: "⬜", PARTIAL: "⚠️", NA: "—", UNKNOWN: "?"}
KNOWN = {SHIPPED, WIP, TODO, PARTIAL, NA}
# "behind a shipped peer" counts WIP/TODO/PARTIAL — but NOT unrecognized cells (those are warnings).
NOT_DONE = {WIP, TODO, PARTIAL}
_NA_LITERALS = {"", "-", "—", "–", "n/a", "na"}  # em-dash, en-dash, ascii dash, n/a variants


def find_root(start: Path) -> Path:
    for d in [start, *start.parents]:
        if (d / "PARITY.md").is_file() and (d / "conformance").is_dir():
            return d
    raise SystemExit("parity-drift: could not locate repo root (PARITY.md + conformance/).")


def classify(cell: str) -> str:
    c = cell.strip()
    if "✅" in c:
        return SHIPPED
    if "🚧" in c:
        return WIP
    if "⚠" in c:  # ⚠️ may carry a U+FE0F variation selector
        return PARTIAL
    if "⬜" in c:
        return TODO
    if c.lower() in _NA_LITERALS or c.startswith("—") or c.startswith("–"):
        return NA
    return UNKNOWN


def split_row(line: str) -> list[str]:
    """Split a markdown table row on '|' — but ignore '|' inside `inline code` spans, so feature
    names / vector cells containing a pipe (e.g. a regex `a|b`) don't shift every column."""
    cells, buf, in_code = [], [], False
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    for ch in s:
        if ch == "`":
            in_code = not in_code
            buf.append(ch)
        elif ch == "|" and not in_code:
            cells.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    cells.append("".join(buf).strip())
    return cells


def is_separator(cells: list[str]) -> bool:
    return bool(cells) and all(re.fullmatch(r":?-+:?", c) or c == "" for c in cells)


def parse_tables_with_headings(md: str):
    """Yield (heading_lower, rows) for each pipe-table, tagged with the nearest preceding heading."""
    tables, cur, heading = [], [], ""
    for line in md.splitlines():
        s = line.strip()
        if s.startswith("#"):
            if cur:
                tables.append((heading, cur)); cur = []
            heading = s.lstrip("#").strip().lower()
        elif s.startswith("|") and s.endswith("|"):
            cells = split_row(s)
            if is_separator(cells):
                continue
            cur.append(cells)
        else:
            if cur:
                tables.append((heading, cur)); cur = []
    if cur:
        tables.append((heading, cur))
    return tables


def _pad(row, n):
    return row + [""] * (n - len(row)) if len(row) < n else row


def parse_parity(path: Path):
    md = path.read_text(encoding="utf-8")
    tables = parse_tables_with_headings(md)

    feature_table = None
    for _, t in tables:
        lower = [c.lower() for c in t[0]]
        if "feature" in lower and "spec" in lower:
            feature_table = t
            break
    if not feature_table:
        raise SystemExit("parity-drift: feature×platform table not found in PARITY.md.")

    header = feature_table[0]
    lower = [h.lower() for h in header]
    idx_feature = lower.index("feature")
    idx_spec = lower.index("spec") if "spec" in lower else None
    idx_conf = lower.index("conformance") if "conformance" in lower else None
    reserved = {i for i in (idx_feature, idx_spec, idx_conf) if i is not None}
    data_rows = [_pad(r, len(header)) for r in feature_table[1:] if r and r[idx_feature].strip()]

    # A column is a *platform* column iff it's not Feature/Spec/Conformance AND most of its data
    # cells are recognized status glyphs — so a free-text "Notes"/"Owner" column isn't mistaken
    # for a platform (which would manufacture phantom drift).
    platform_cols = []
    quorum = max(1, math.ceil(len(data_rows) / 2)) if data_rows else 1
    for i in range(len(header)):
        if i in reserved:
            continue
        recognized = sum(1 for r in data_rows if classify(r[i]) in KNOWN)
        if recognized >= quorum:
            platform_cols.append((i, header[i]))
    platforms = [name for _, name in platform_cols]

    features = []
    for r in data_rows:
        spec = r[idx_spec] if idx_spec is not None else ""
        conf = r[idx_conf] if idx_conf is not None else ""
        vectors = [t.strip() for t in re.findall(r"`([^`]+)`", conf)]
        # the manifest is referenced like a vector but isn't one
        manifest = any(_is_manifest(v) for v in vectors)
        vecs = [_vec_stem(v) for v in vectors if not _is_manifest(v)]
        kind = "logic" if vecs else ("backend" if manifest else "ui")
        features.append({
            "feature": r[idx_feature], "spec": spec, "conf": conf,
            "kind": kind, "vectors": vecs,
            "status": {name: classify(r[i]) for i, name in platform_cols},
        })

    # version table: anchor on the "## Version" heading; map its columns to the SAME platform names.
    versions, schema, version_table_found = {}, {}, False
    vt = next((t for h, t in tables if "version" in h and len(t) >= 1), None)
    if vt:
        version_table_found = True
        vheader = vt[0]
        # match each version-table column to a feature platform by case-insensitive name
        col_to_platform = {}
        for i, h in enumerate(vheader):
            for p in platforms:
                if h.strip().lower() == p.strip().lower():
                    col_to_platform[i] = p
        for r in vt[1:]:
            if not r:
                continue
            label = r[0].lower()
            target = schema if "schema" in label else (versions if "version" in label else None)
            if target is None:
                continue
            for i, p in col_to_platform.items():
                cell = r[i].strip() if i < len(r) else ""
                if target is versions:
                    m = re.search(r"(\d+)\.(\d+)", cell)
                    target[p] = f"{m.group(1)}.{m.group(2)}" if m else ("na" if classify(cell) == NA else cell)
                else:
                    target[p] = "na" if classify(cell) == NA else cell

    return {"platforms": platforms, "features": features, "versions": versions,
            "schema": schema, "version_table_found": version_table_found}


def _is_manifest(token: str) -> bool:
    t = token.strip().lower()
    return t.endswith("backends.json") or t.startswith("spec/backends")


def _vec_stem(token: str) -> str:
    t = token.strip()
    return t[:-5] if t.endswith(".json") else t


def compute(root: Path):
    parity = parse_parity(root / "PARITY.md")
    platforms = parity["platforms"]
    features = parity["features"]

    def action(feat, platform):
        if feat["kind"] == "logic":
            return f"→ make conformance/{feat['vectors'][0]}.json pass on {platform} (Law 2)"
        if feat["kind"] == "backend":
            return "→ implement via spec/backends.json declarative manifest (Law 6)"
        spec = feat["spec"] if classify(feat["spec"]) != NA else "(no spec — add one, Law 1)"
        return f"→ implement per spec {spec} + per-platform UI check (no vector gate)"

    behind = {p: [] for p in platforms}
    unbuilt, unrecognized = [], []
    for f in features:
        st = f["status"]
        for p in platforms:
            if st[p] == UNKNOWN:
                unrecognized.append({"feature": f["feature"], "platform": p})
        leaders = [p for p in platforms if st[p] == SHIPPED]
        applicable = [p for p in platforms if st[p] != NA]
        if leaders:
            for p in platforms:
                if st[p] in NOT_DONE:
                    behind[p].append({"feature": f["feature"], "status": st[p], "kind": f["kind"],
                                      "leaders": leaders, "spec": f["spec"], "action": action(f, p)})
        elif applicable:
            unbuilt.append({"feature": f["feature"], "kind": f["kind"],
                            "status": {p: st[p] for p in applicable}})

    # Law 3: platforms declaring the SAME MAJOR.MINOR must have the SAME ✅ set.
    ver_mm = {p: v for p, v in parity["versions"].items() if re.fullmatch(r"\d+\.\d+", str(v))}
    law3 = []
    by_version = {}
    for p, v in ver_mm.items():
        by_version.setdefault(v, []).append(p)
    for v, ps in by_version.items():
        if len(ps) < 2:
            continue
        for f in features:
            st = f["status"]
            inscope = [p for p in ps if st[p] != NA]
            shipped = [p for p in inscope if st[p] == SHIPPED]
            if shipped and len(shipped) != len(inscope):
                lagging = [p for p in inscope if st[p] != SHIPPED]
                law3.append({"version": v, "feature": f["feature"],
                             "shipped": shipped, "lagging": lagging})

    def vals(d):
        return {p: x for p, x in d.items() if x != "na"}
    vv, vs = vals(parity["versions"]), vals(parity["schema"])
    version_drift = len(set(vv.values())) > 1
    schema_drift = len(set(vs.values())) > 1

    conf_dir = root / "conformance"
    on_disk = {p.stem for p in conf_dir.glob("*.json")}
    referenced = {v for f in features for v in f["vectors"]}
    orphans = sorted(on_disk - referenced)
    dangling = sorted(referenced - on_disk)
    manifest_present = (root / "spec" / "backends.json").is_file()

    # spec gaps: a feature has a spec iff its Spec cell carries a § reference.
    has_section = lambda s: bool(re.search(r"§\s*\d", s))
    no_spec = [f["feature"] for f in features if not has_section(f["spec"])]
    shipped_without_spec = [f["feature"] for f in features
                            if not has_section(f["spec"]) and SHIPPED in f["status"].values()]

    warnings = []
    if features and not parity["version_table_found"]:
        warnings.append("Version table not found under a '## Version' heading — version/schema drift unchecked.")
    if features and parity["version_table_found"] and not vv:
        warnings.append("Version table found but no platform versions parsed (column names may not match the feature table).")
    for u in unrecognized:
        warnings.append(f"Unrecognized status cell: '{u['feature']}' @ {u['platform']} (typo? not counted as drift).")

    return {
        "schema_version": JSON_SCHEMA_VERSION,
        "basis": "manual PARITY.md declarations; does NOT run platform tests (Law 2 truth = CI vectors green)",
        "platforms": platforms,
        "behind": behind,
        "law3_violations": law3,
        "unbuilt": unbuilt,
        "versions": parity["versions"],
        "schema": parity["schema"],
        "version_drift": version_drift,
        "schema_drift": schema_drift,
        "conformance": {"on_disk": sorted(on_disk), "referenced": sorted(referenced),
                        "orphans": orphans, "dangling": dangling, "manifest_present": manifest_present},
        "spec": {"no_spec": no_spec, "shipped_without_spec": shipped_without_spec},
        "warnings": warnings,
        "features": features,
    }


def has_drift(r, strict=False) -> bool:
    core = (sum(len(v) for v in r["behind"].values()) > 0
            or bool(r["law3_violations"]) or r["version_drift"] or r["schema_drift"]
            or bool(r["conformance"]["dangling"]))
    if strict:
        core = core or bool(r["conformance"]["orphans"]) or bool(r["spec"]["shipped_without_spec"])
    return core


def render_text(r, strict=False) -> str:
    o, P = [], r["platforms"]
    o.append("PARITY DRIFT REPORT")
    o.append("=" * 64)
    o.append(f"SOURCE: {r['basis']}.")

    o.append("\n## 1. Feature drift (behind a shipped peer)")
    total_behind = sum(len(v) for v in r["behind"].values())
    for p in P:
        items = r["behind"][p]
        if not items:
            o.append(f"\n  {p}: ✓ up to date")
            continue
        o.append(f"\n  {p}: {len(items)} behind")
        for it in items:
            o.append(f"    [{GLYPH[it['status']]}] {it['feature']}  ({it['kind']}; shipped on {', '.join(it['leaders'])})")
            o.append(f"         {it['action']}")
    if total_behind == 0:
        o.append("\n  → every shipped feature is shipped on all applicable platforms.")

    o.append("\n## 2. Law 3 — same MAJOR.MINOR must mean same feature set")
    if r["law3_violations"]:
        for v in r["law3_violations"]:
            o.append(f"  ⚠️ v{v['version']}: '{v['feature']}' shipped on {', '.join(v['shipped'])} "
                     f"but NOT on {', '.join(v['lagging'])}")
    else:
        o.append("  ✓ no two platforms declare the same MAJOR.MINOR with a different feature set.")

    o.append("\n## 3. Version / schema drift")
    ver = "  ".join(f"{p}={r['versions'].get(p, '?')}" for p in P)
    sch = "  ".join(f"{p}={r['schema'].get(p, '?')}" for p in P)
    o.append(f"  app MAJOR.MINOR: {ver}   " + ("⚠️ DRIFT" if r["version_drift"] else "OK"))
    o.append(f"  config schema:   {sch}   " + ("⚠️ DRIFT" if r["schema_drift"] else "OK"))

    o.append("\n## 4. Conformance vector coverage")
    c = r["conformance"]
    o.append(f"  on disk ({len(c['on_disk'])}): {', '.join(c['on_disk'])}")
    o.append(f"  orphan vectors (no feature row): {', '.join(c['orphans']) or 'none'}" + ("   ⚠️ (gate: --strict)" if c["orphans"] else ""))
    o.append(f"  dangling refs (→ missing file): {', '.join(c['dangling']) or 'none'}" + ("   ⚠️ DRIFT" if c["dangling"] else ""))
    o.append(f"  spec/backends.json present: {'yes' if c['manifest_present'] else 'NO ⚠️'}")

    o.append("\n## 5. Spec gaps")
    sg = r["spec"]
    o.append(f"  no § reference: {', '.join(sg['no_spec']) or 'none'}")
    o.append(f"  SHIPPED but no spec (Law 1 ⚠️{', gate: --strict' if sg['shipped_without_spec'] else ''}): {', '.join(sg['shipped_without_spec']) or 'none'}")

    o.append("\n## 6. Not built on any platform yet (info, not gated)")
    o.append("  " + ("; ".join(f"{u['feature']} [{u['kind']}]" for u in r["unbuilt"]) if r["unbuilt"] else "none"))

    if r["warnings"]:
        o.append("\n## ⚠ Warnings")
        for w in r["warnings"]:
            o.append(f"  - {w}")

    drift = has_drift(r, strict)
    o.append("\n" + "=" * 64)
    o.append(f"SUMMARY: behind={total_behind}  law3={len(r['law3_violations'])}  version_drift={r['version_drift']}  "
             f"schema_drift={r['schema_drift']}  dangling={len(c['dangling'])}  orphans={len(c['orphans'])}  "
             f"shipped_without_spec={len(sg['shipped_without_spec'])}")
    o.append("RESULT: " + ("⚠️  DRIFT DETECTED" if drift else "✓ DECLARED-ALIGNED (PARITY claims consistent — not a test run)"))
    return "\n".join(o)


def render_digest(r) -> str:
    """One compact block for session-start surfacing: what cross-platform alignment is pending."""
    P = r["platforms"]
    behind = r["behind"]
    total = sum(len(v) for v in behind.values())
    if not has_drift(r):
        return "PARITY ✓ declared-aligned — no pending cross-platform alignment tasks."
    out = [f"⚠ PARITY DRIFT — {total} pending cross-platform alignment item(s) "
           "(declared in PARITY.md; run `python3 scripts/parity-drift.py` for detail + per-item actions):"]
    for p in P:
        items = behind[p]
        if not items:
            continue
        names = [it["feature"] for it in items]
        shown = "; ".join(names[:3]) + (f"  (+{len(names) - 3} more)" if len(names) > 3 else "")
        out.append(f"  • {p}: {len(items)} behind a shipped peer — {shown}")
    if r["law3_violations"]:
        out.append(f"  • Law-3: {len(r['law3_violations'])} same-version / different-feature-set violation(s)")
    out.append("  → Per the Constitution, package the items for the platform you are working on into "
               "TODO tasks and surface them before other work.")
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Cross-platform parity drift report (reads PARITY.md declarations).")
    ap.add_argument("--root", type=Path, default=None, help="repo root (auto-detected if omitted)")
    ap.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    ap.add_argument("--digest", action="store_true", help="compact session-start summary of pending tasks")
    ap.add_argument("--fail-on-drift", action="store_true", help="exit 1 if drift is detected")
    ap.add_argument("--strict", action="store_true", help="also gate on orphan vectors + shipped-without-spec")
    args = ap.parse_args(argv)

    root = args.root.resolve() if args.root else find_root(Path(__file__).resolve().parent)
    r = compute(root)
    drift = has_drift(r, args.strict)

    if args.digest:
        print(render_digest(r))
        return 0
    if args.json:
        out = dict(r)
        out["has_drift"] = drift
        out["result"] = "drift" if drift else "declared-aligned"
        out["summary"] = {
            "behind": sum(len(v) for v in r["behind"].values()),
            "law3_violations": len(r["law3_violations"]),
            "version_drift": r["version_drift"], "schema_drift": r["schema_drift"],
            "dangling": len(r["conformance"]["dangling"]), "orphans": len(r["conformance"]["orphans"]),
            "shipped_without_spec": len(r["spec"]["shipped_without_spec"]),
        }
        print(json.dumps(out, ensure_ascii=False, indent=2))
    else:
        print(render_text(r, args.strict))

    return 1 if (args.fail_on_drift and drift) else 0


if __name__ == "__main__":
    sys.exit(main())

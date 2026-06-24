#!/usr/bin/env python3
"""Single-command app-version bump across both platforms + PARITY (spec §12).

ONE marketing version (`MAJOR.MINOR.PATCH`), coordinated across platforms (Law 3: same `MAJOR.MINOR`
= same feature set). Before this script a bump meant hand-editing ~8 spots and it was easy to miss one
(the macOS settings caption once lagged because the built bundle was stale; a Swift fallback sat at a
stale `0.2.0`). This moves every REQUIRED source together so a bump can't drift:

  - Windows : platforms/windows/src/TranslateTheDamn.App/TranslateTheDamn.App.csproj  <Version>
              (FileVersion / AssemblyVersion / InformationalVersion DERIVE from it — one field only)
  - macOS   : platforms/macos/Resources/Info.plist  CFBundleShortVersionString  (+ CFBundleVersion++)
  - PARITY.md  Version table (Win + macOS columns)

Everything else reads the version at RUNTIME (Windows from the assembly, macOS from the bundle), and the
screenshot/walkthrough fallbacks are non-version sentinels ("dev"), so no other file carries a version
literal to keep in sync.

Usage:
  scripts/bump-version.py 0.4.0       # set the version everywhere (CFBundleVersion auto-increments)
  scripts/bump-version.py --check     # verify every source already agrees (CI / pre-release guard)
Exit: 0 ok; 1 mismatch (--check) or bad version; 2 file problem.

After a set: rebuild macOS (`platforms/macos/scripts/build-app.sh` — the caption reads the BUILT bundle,
not the source plist) and, to publish, tag `v<version>` (release.yml's per-platform version-match guards
then require the built artifacts to report it). Zero deps (Python 3.8+ stdlib).
"""
import re
import sys
from pathlib import Path

SEMVER = re.compile(r"^\d+\.\d+\.\d+$")


def find_root(start: Path) -> Path:
    for d in [start, *start.parents]:
        if (d / "PARITY.md").is_file() and (d / "platforms").is_dir():
            return d
    raise SystemExit("bump-version: could not locate repo root (PARITY.md + platforms/).")


def paths(root: Path):
    return {
        "csproj": root / "platforms/windows/src/TranslateTheDamn.App/TranslateTheDamn.App.csproj",
        "plist": root / "platforms/macos/Resources/Info.plist",
        "parity": root / "PARITY.md",
    }


def read_csproj(p: Path):
    m = re.search(r"<Version>([^<]+)</Version>", p.read_text(encoding="utf-8"))
    return m.group(1).strip() if m else None


def read_plist(p: Path):
    t = p.read_text(encoding="utf-8")
    sv = re.search(r"<key>CFBundleShortVersionString</key>\s*<string>([^<]*)</string>", t)
    bv = re.search(r"<key>CFBundleVersion</key>\s*<string>([^<]*)</string>", t)
    return (sv.group(1).strip() if sv else None, bv.group(1).strip() if bv else None)


def read_parity(p: Path):
    """Return (win, macos) version cells from the '| App version | **x** | **y** ... |' row."""
    for line in p.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("| App version"):
            nums = re.findall(r"\*\*(\d+\.\d+\.\d+)\*\*", line)
            if len(nums) >= 2:
                return nums[0], nums[1]
    return None, None


def collect(root: Path):
    pp = paths(root)
    csproj = read_csproj(pp["csproj"])
    plist_short, plist_build = read_plist(pp["plist"])
    parity_win, parity_mac = read_parity(pp["parity"])
    return {
        "Windows csproj <Version>": csproj,
        "macOS CFBundleShortVersionString": plist_short,
        "PARITY Win column": parity_win,
        "PARITY macOS column": parity_mac,
    }, plist_build


def do_check(root: Path) -> int:
    sources, build = collect(root)
    print("bump-version --check:")
    for k, v in sources.items():
        print(f"  {v or '??':<8} {k}")
    print(f"  (macOS CFBundleVersion build number: {build or '??'})")
    vals = [v for v in sources.values() if v]
    missing = [k for k, v in sources.items() if not v]
    if missing:
        print("  ✗ could not read: " + ", ".join(missing))
        return 1
    if len(set(vals)) != 1:
        print(f"  ✗ VERSION DRIFT — sources disagree: {sorted(set(vals))}. "
              f"Run `scripts/bump-version.py <version>` to re-sync.")
        return 1
    print(f"  ✓ all version sources agree at {vals[0]}.")
    return 0


def sub_once(text: str, pattern: str, repl: str, where: str) -> str:
    new, n = re.subn(pattern, repl, text, count=1)
    if n != 1:
        raise SystemExit(f"bump-version: expected exactly 1 match for {where}, found {n}.")
    return new


def do_set(root: Path, version: str) -> int:
    if not SEMVER.match(version):
        print(f"bump-version: {version!r} is not MAJOR.MINOR.PATCH (e.g. 0.4.0).")
        return 1
    pp = paths(root)
    for key, p in pp.items():
        if not p.is_file():
            print(f"bump-version: missing {key} file {p}")
            return 2

    # Windows csproj — the single <Version> field (the rest derive from it).
    t = pp["csproj"].read_text(encoding="utf-8")
    t = sub_once(t, r"<Version>[^<]+</Version>", f"<Version>{version}</Version>", "csproj <Version>")
    pp["csproj"].write_text(t, encoding="utf-8")

    # macOS Info.plist — marketing version + monotonic build number (CFBundleVersion++).
    t = pp["plist"].read_text(encoding="utf-8")
    t = sub_once(t, r"(<key>CFBundleShortVersionString</key>\s*<string>)[^<]*(</string>)",
                 lambda m: m.group(1) + version + m.group(2), "CFBundleShortVersionString")
    _, build = read_plist(pp["plist"])
    next_build = str(int(build) + 1) if (build and build.isdigit()) else "1"
    t = sub_once(t, r"(<key>CFBundleVersion</key>\s*<string>)[^<]*(</string>)",
                 lambda m: m.group(1) + next_build + m.group(2), "CFBundleVersion")
    pp["plist"].write_text(t, encoding="utf-8")

    # PARITY Version table — both platform cells on the 'App version' row.
    lines = pp["parity"].read_text(encoding="utf-8").splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.lstrip().startswith("| App version"):
            lines[i] = re.sub(r"\*\*\d+\.\d+\.\d+\*\*", f"**{version}**", line)
            break
    pp["parity"].write_text("".join(lines), encoding="utf-8")

    print(f"bump-version: set {version} everywhere (macOS CFBundleVersion → {next_build}).")
    print("  next: rebuild macOS (platforms/macos/scripts/build-app.sh) so the settings caption updates")
    print("        (it reads the BUILT bundle, not the source plist); then `scripts/bump-version.py --check`.")
    print(f"        to publish: tag v{version} (release.yml version-match guards then require {version}).")
    return do_check(root)


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    root = find_root(Path(__file__).resolve().parent)
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[0] == "--check":
        return do_check(root)
    return do_set(root, argv[0].lstrip("v"))


if __name__ == "__main__":
    sys.exit(main())

#!/bin/bash
# screenshot-ui.sh — capture the full screenshot matrix for the UI-style review
# (docs/UI-STYLE-REVIEW.md): every style's settings window + translation popup, in light AND
# dark appearance, acrylic AND solid popup materials, and every settings sub-page for the tabbed
# (O48) / sidebar (KM) styles.
#
# Pairs with src/App/ScreenshotHarness.swift (dev-only, env-gated). It launches the debug build
# with TTD_SHOT_* env vars, waits for the harness to publish the on-screen window id, then grabs
# that exact window with `screencapture -l<id>` (titlebar + real vibrancy, no accessibility).
#
# Requirements: the invoking terminal must have macOS Screen Recording permission (for
# `screencapture`). Run `swift build` first (this script uses the debug binary).
#
# Usage:
#   ./platforms/macos/scripts/screenshot-ui.sh                                  # full matrix (54 shots)
#   ./platforms/macos/scripts/screenshot-ui.sh <kind> <style> <pstyle> <mode> <page> <outPath>
#     kind: settings|popup  style: classic|ZP|km|O48|Z|MM|DS
#     pstyle: acrylic|solid  mode: light|dark  page: 0..3 (O48 tab / KM sidebar; else 0)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO="$(cd "${MAC}/../.." && pwd)"
BIN="${MAC}/.build/debug/TranslateTheDamnApp"
SHOTS="${REPO}/docs/ui-review/shots"
STYLES="classic ZP km O48 Z MM DS"

shoot() {  # kind style pstyle mode page outPath
  local kind="$1" style="$2" pstyle="$3" mode="$4" page="$5" out="$6"
  local ready; ready="$(mktemp /tmp/ttd-ready.XXXXXX)"; rm -f "$ready" "$out"
  pkill -f "TranslateTheDamnApp" 2>/dev/null; sleep 0.3
  TTD_SHOT_KIND="$kind" TTD_SHOT_STYLE="$style" TTD_SHOT_POPUP_STYLE="$pstyle" \
    TTD_SHOT_APPEARANCE="$mode" TTD_SHOT_PAGE="$page" TTD_SHOT_READY="$ready" \
    "$BIN" >/tmp/ttd-shot-last.log 2>&1 &
  local pid=$!
  local i; for i in $(seq 1 80); do [ -s "$ready" ] && break; sleep 0.1; done
  local win; win="$(cat "$ready" 2>/dev/null)"
  sleep 0.5
  screencapture -l"$win" -o "$out" 2>/dev/null
  kill "$pid" 2>/dev/null; rm -f "$ready"
  if [ -f "$out" ]; then echo "OK  $(basename "$out")"; else echo "FAIL $kind/$style/$pstyle/$mode/p$page (win=$win)"; fi
}

if [ ! -x "$BIN" ]; then echo "Build first: (cd $MAC && swift build)"; exit 1; fi

if [ "$#" -eq 6 ]; then
  shoot "$1" "$2" "$3" "$4" "$5" "$6"; pkill -f "TranslateTheDamnApp" 2>/dev/null; exit 0
fi

mkdir -p "$SHOTS"
# suffix for non-light/non-tab0: "" for light, "-dark" for dark
sfx() { [ "$1" = dark ] && echo "-dark" || echo ""; }

# --- Settings ---
for mode in light dark; do
  for s in classic ZP Z MM DS; do
    shoot settings "$s" acrylic "$mode" 0 "$SHOTS/settings-$s$(sfx "$mode").png"
  done
  for s in O48 km; do
    for p in 0 1 2 3; do
      if [ "$p" = 0 ]; then nm="settings-$s$(sfx "$mode").png"; else nm="settings-$s-tab$p$(sfx "$mode").png"; fi
      shoot settings "$s" acrylic "$mode" "$p" "$SHOTS/$nm"
    done
  done
done

# --- Popups: 7 styles x {acrylic,solid} x {light,dark} ---
for mode in light dark; do
  for mat in acrylic solid; do
    for s in $STYLES; do
      shoot popup "$s" "$mat" "$mode" 0 "$SHOTS/popup-$s-$mat$(sfx "$mode").png"
    done
  done
done

pkill -f "TranslateTheDamnApp" 2>/dev/null
echo "Done. $(ls "$SHOTS"/*.png | wc -l | tr -d ' ') shots in $SHOTS"

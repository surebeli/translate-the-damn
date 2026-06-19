#!/bin/bash
# screenshot-ui.sh — capture real composited screenshots of every UI style's settings
# window and translation popup, for the UI-style review (docs/UI-STYLE-REVIEW.md).
#
# Pairs with src/App/ScreenshotHarness.swift (dev-only, env-gated). It launches the debug
# build with TTD_SHOT_* env vars, waits for the harness to publish the on-screen window id,
# then grabs that exact window with `screencapture -l<id>` (titlebar + real vibrancy, no
# accessibility / tray-clicking needed).
#
# Requirements: the invoking terminal must have macOS Screen Recording permission (needed by
# `screencapture`). Run `swift build` first (this script uses the debug binary).
#
# Usage:
#   ./platforms/macos/scripts/screenshot-ui.sh            # capture the full review set
#   ./platforms/macos/scripts/screenshot-ui.sh <kind> <style> <popupStyle> <outPath>
#     kind: settings|popup   style: classic|ZP|km|O48|Z|MM|DS   popupStyle: acrylic|solid
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO="$(cd "${MAC}/../.." && pwd)"
BIN="${MAC}/.build/debug/TranslateTheDamnApp"
SHOTS="${REPO}/docs/ui-review/shots"
STYLES="classic ZP km O48 Z MM DS"

shoot() {  # kind style popupStyle outPath
  local kind="$1" style="$2" pstyle="$3" out="$4"
  local ready; ready="$(mktemp /tmp/ttd-ready.XXXXXX)"; rm -f "$ready" "$out"
  pkill -f "TranslateTheDamnApp" 2>/dev/null; sleep 0.3
  TTD_SHOT_KIND="$kind" TTD_SHOT_STYLE="$style" TTD_SHOT_POPUP_STYLE="$pstyle" TTD_SHOT_READY="$ready" \
    "$BIN" >/tmp/ttd-shot-last.log 2>&1 &
  local pid=$!
  local i; for i in $(seq 1 80); do [ -s "$ready" ] && break; sleep 0.1; done
  local win; win="$(cat "$ready" 2>/dev/null)"
  sleep 0.5
  screencapture -l"$win" -o "$out" 2>/dev/null
  kill "$pid" 2>/dev/null; rm -f "$ready"
  if [ -f "$out" ]; then echo "OK  $kind/$style/$pstyle -> $out"; else echo "FAIL $kind/$style/$pstyle (win=$win)"; fi
}

if [ ! -x "$BIN" ]; then echo "Build first: (cd $MAC && swift build)"; exit 1; fi

if [ "$#" -eq 4 ]; then
  shoot "$1" "$2" "$3" "$4"; pkill -f "TranslateTheDamnApp" 2>/dev/null; exit 0
fi

mkdir -p "$SHOTS"
for s in $STYLES; do shoot settings "$s" acrylic "$SHOTS/settings-$s.png"; done
for s in $STYLES; do shoot popup "$s" acrylic "$SHOTS/popup-$s-acrylic.png"; done
shoot popup O48 solid "$SHOTS/popup-O48-solid.png"
pkill -f "TranslateTheDamnApp" 2>/dev/null
echo "Done. Shots in $SHOTS"

#!/bin/bash
# Visual-walkthrough capture: render each UI state (light+dark) and screencapture the real window.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT="${PROJECT_DIR}/.shots"
BIN="${PROJECT_DIR}/.build/release/TranslateTheDamnApp"
# Real version from Info.plist (the raw binary has no bundle, so pass it in for the settings title).
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${PROJECT_DIR}/Resources/Info.plist" 2>/dev/null || echo 0.4.0)"
export TTD_SHOT_VERSION="$VERSION"
rm -rf "${OUT}"; mkdir -p "${OUT}"

KINDS=(popup-result popup-large popup-loading popup-error popup-history \
       settings-builtin settings-http settings-custom settings-backends \
       settings-lamp-checking settings-lamp-ok settings-lamp-fail)

for kind in "${KINDS[@]}"; do
  for appr in light dark; do
    ready="$(mktemp)"; rm -f "$ready"
    TTD_SHOT_KIND="$kind" TTD_SHOT_APPEARANCE="$appr" TTD_SHOT_READY="$ready" "$BIN" >/dev/null 2>&1 &
    pid=$!
    for _ in $(seq 1 40); do [ -s "$ready" ] && break; sleep 0.1; done
    sleep 0.5
    wid="$(cat "$ready" 2>/dev/null || echo -1)"
    if [ "$wid" -gt 0 ]; then
      screencapture -l"$wid" -o -x -t png "${OUT}/${kind}-${appr}.png" 2>/dev/null || echo "  capture failed $kind $appr"
    else
      echo "  no window id for $kind $appr"
    fi
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
done
echo "shots → ${OUT}"
ls -1 "${OUT}"

#!/bin/bash
# sign-notarize.sh — Code-sign + notarize + staple TranslateTheDamn.app for distribution.
#
# Usage:
#   export DEVELOPER_ID="Developer ID Application: Your Name (TEAMXXXXXXXXX)"
#   export APPLE_ID="your@email.com"
#   export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
#   export TEAM_ID="TEAMXXXXXXXXX"
#   ./platforms/macos/scripts/sign-notarize.sh
#
# All credentials are passed via environment variables. Nothing is hardcoded.
#
# Prerequisites: Xcode CLT, Apple Developer account, app-specific password for notarytool.
# NO App Sandbox (the app must spawn user CLIs).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_PATH="${PROJECT_DIR}/TranslateTheDamn.app"

die() { echo "ERROR: $*" >&2; exit 1; }

# --- Parameter validation ---
: "${DEVELOPER_ID:?Set DEVELOPER_ID env var (e.g. \"Developer ID Application: Your Name (TEAMXXXXXXXXX)\")}"
: "${APPLE_ID:?Set APPLE_ID env var (your Apple ID email)}"
: "${APP_PASSWORD:?Set APP_PASSWORD env var (app-specific password)}"
: "${TEAM_ID:?Set TEAM_ID env var (your Apple Developer Team ID)}"

[ -d "${APP_PATH}" ] || die "App bundle not found at ${APP_PATH}. Run build-app.sh first."

echo "=== Step 1/3: Code-sign (hardened runtime, no sandbox) ==="
codesign --deep --force --options runtime --sign "${DEVELOPER_ID}" "${APP_PATH}"
codesign --verify --verbose "${APP_PATH}"

echo "=== Step 2/3: Notarize ==="
xcrun notarytool submit "${APP_PATH}" \
    --apple-id "${APPLE_ID}" \
    --password "${APP_PASSWORD}" \
    --team-id "${TEAM_ID}" \
    --wait

echo "=== Step 3/3: Staple ==="
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"

echo ""
echo "=== Signing + notarization complete ==="
echo "  App: ${APP_PATH}"
echo "  Verify with: spctl --assess --verbose ${APP_PATH}"

#!/bin/bash
# build-app.sh — Build release executable and wrap it into TranslateTheDamn.app
#
# Usage:
#   ./platforms/macos/scripts/build-app.sh
#
# Produces: platforms/macos/TranslateTheDamn.app
#
# Requirements: Xcode CLT (swift, iconutil, plutil). arm64 only.
#
# NO App Sandbox (the app must spawn user CLIs).
# Signing/notarization is a separate step — see sign-notarize.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${PROJECT_DIR}/../.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build"
APP_DIR="${PROJECT_DIR}/TranslateTheDamn.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
EXECUTABLE_NAME="TranslateTheDamn"
# The SwiftPM executable target is named TranslateTheDamnApp (Package.swift target name).
# We copy it into the .app bundle as TranslateTheDamn (matching CFBundleExecutable in Info.plist).
SWIFTPM_TARGET="TranslateTheDamnApp"

echo "=== Step 1/5: swift build -c release ==="
cd "${PROJECT_DIR}"
swift build -c release

RELEASE_BIN="${BUILD_DIR}/release/${SWIFTPM_TARGET}"
if [ ! -x "${RELEASE_BIN}" ]; then
    echo "ERROR: Release binary not found at ${RELEASE_BIN}" >&2
    exit 1
fi

ARCH="$(file -b "${RELEASE_BIN}" | grep -o 'arm64\|x86_64' || true)"
if [ "${ARCH}" != "arm64" ]; then
    echo "WARNING: Expected arm64 but got ${ARCH:-unknown}. Build may not match target." >&2
fi
echo "  Binary arch: ${ARCH:-unknown}"

echo "=== Step 2/5: Create .app bundle structure ==="
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "=== Step 3/5: Copy executable ==="
cp "${RELEASE_BIN}" "${MACOS_DIR}/${EXECUTABLE_NAME}"

echo "=== Step 4/5: Copy resources ==="
cp "${PROJECT_DIR}/Resources/app.icns" "${RESOURCES_DIR}/app.icns"

# Copy ALL locale catalogs (i18n) — StringsLoader resolves strings/<locale>.json at runtime.
mkdir -p "${RESOURCES_DIR}/strings"
cp "${REPO_ROOT}"/strings/*.json "${RESOURCES_DIR}/strings/"

BACKENDS_SRC="${REPO_ROOT}/spec/backends.json"
cp "${BACKENDS_SRC}" "${RESOURCES_DIR}/backends.json"

echo "=== Step 5/5: Copy Info.plist ==="
cp "${PROJECT_DIR}/Resources/Info.plist" "${CONTENTS_DIR}/Info.plist"

echo ""
echo "=== Bundle complete ==="
echo "  App: ${APP_DIR}"
echo "  Executable: ${MACOS_DIR}/${EXECUTABLE_NAME}"
echo "  Resources:"
ls -la "${RESOURCES_DIR}/"
echo "  Info.plist present: $([ -f "${CONTENTS_DIR}/Info.plist" ] && echo 'yes' || echo 'MISSING')"

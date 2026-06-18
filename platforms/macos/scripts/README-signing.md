# Signing & Notarization for TranslateTheDamn.app

The `sign-notarize.sh` script code-signs, notarizes, and staples the `.app` bundle
for macOS distribution. It is **parameterized** — all credentials come from
environment variables.

## Prerequisites

- A paid Apple Developer Program membership.
- A **Developer ID Application** certificate in your keychain (check with
  `security find-identity -v -p macappstore`).
- An **app-specific password** for your Apple ID (create one at
  [appleid.apple.com](https://appleid.apple.com)).
- Xcode Command Line Tools installed (`xcode-select --install`).

## Usage

```bash
# 1. Build the .app bundle first
./platforms/macos/scripts/build-app.sh

# 2. Sign + notarize
export DEVELOPER_ID="Developer ID Application: Your Name (TEAMXXXXXXXXX)"
export APPLE_ID="your@email.com"
export APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export TEAM_ID="TEAMXXXXXXXXX"
./platforms/macos/scripts/sign-notarize.sh
```

After notarization, verify with:

```bash
spctl --assess --verbose platforms/macos/TranslateTheDamn.app
xcrun stapler validate platforms/macos/TranslateTheDamn.app
```

## Environment variables

| Variable       | Description                                                      |
|---------------|------------------------------------------------------------------|
| `DEVELOPER_ID` | Full identity string of your Developer ID certificate.           |
| `APPLE_ID`     | Apple ID email address.                                          |
| `APP_PASSWORD` | App-specific password (NOT your Apple ID password).              |
| `TEAM_ID`      | 10-character Apple Developer Team ID.                            |

## Hardened runtime & entitlements

The app is signed with **hardened runtime** (`--options runtime`) but **NO App
Sandbox**, because it must spawn external CLIs (translation backends). No
entitlements plist is used — the default hardened runtime allows spawning
processes.

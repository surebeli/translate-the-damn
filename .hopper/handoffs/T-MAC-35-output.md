---
phase: done
last_progress_at: "2026-06-18T06:02:15.926Z"
last_progress: Task completed successfully.
progress_seq: 2
terminal_event_emitted: true
status: done
end_time: "2026-06-18T06:02:15.925Z"
exit_code: 0
signal: null
timed_out: null
duration_ms: 213598
adapter_status: success
---
# T-MAC-35 Output — Start-at-login (SMAppService) + App Icon

## Summary
Implemented macOS start-at-login via `SMAppService` and a unified app-icon build script.
`LoginService` wraps `SMAppService.mainApp.register()/unregister()` behind `setEnabled(_:)` and
`isEnabled()`, guarded for macOS 13+. `AppDelegate` now applies `general.startWithWindows` both at
launch and when settings are saved; the settings save path calls `LoginService.shared.setEnabled`.
A new `scripts/build-icon.sh` renders the shared "文" glyph at all standard `.iconset` resolutions
and assembles `Resources/app.icns` with `iconutil`.

## Files touched

| Path | Lines | Purpose |
|------|-------|---------|
| `platforms/macos/src/App/LoginService.swift` | 51 new | `SMAppService` wrapper: `setEnabled`, `isEnabled`, macOS 13 guard, error logging. |
| `platforms/macos/scripts/build-icon.sh` | 91 new | Renders "文" glyph to PNGs and runs `iconutil -c icns` → `Resources/app.icns`. |
| `platforms/macos/Resources/app.icns` | generated | macOS app icon bundle produced by the script. |
| `platforms/macos/Package.swift` | +5/-1 | Links `ServiceManagement` framework alongside existing `Carbon`. |
| `platforms/macos/src/App/AppDelegate.swift` | +2 (in 40-line uncommitted delta) | Calls `loginService.setEnabled(...)` on launch and in `hotReload`. |
| `platforms/macos/src/App/SettingsWindow.swift` | +2 (in larger uncommitted delta) | Calls `LoginService.shared.setEnabled(...)` after saving settings; marked `save()` `@MainActor` to satisfy actor isolation. |

## Acceptance verification (6/6)

- ✓ **LoginService `setEnabled(_:)` calls `register()`/`unregister()` with error handling and macOS 13 guard.**
  - verifier: `grep -n 'func setEnabled\|#available(macOS 13\|service.register()\|service.unregister()' platforms/macos/src/App/LoginService.swift`
  - evidence: lines 17–37 contain the guard, register, unregister, and `NSLog` error paths.

- ✓ **LoginService `isEnabled()` queries `SMAppService.mainApp.status`.**
  - verifier: `grep -n 'func isEnabled\|SMAppService.mainApp.status' platforms/macos/src/App/LoginService.swift`
  - evidence: lines 43–48 return `status == .enabled`.

- ✓ **App icon script exists and produces `app.icns` from the single "文" glyph.**
  - verifier: `file platforms/macos/Resources/app.icns && head -n 5 platforms/macos/scripts/build-icon.sh`
  - evidence: `Mac OS X icon, 97047 bytes, "ic12" type`; script renders `文` at 16/32/128/256/512/1024 px and runs `iconutil -c icns`.

- ✓ **AppDelegate applies `startWithWindows` on launch and on settings change.**
  - verifier: `grep -n 'loginService.setEnabled(config.general.startWithWindows)' platforms/macos/src/App/AppDelegate.swift`
  - evidence: line 36 (launch) and line 113 (`hotReload`).

- ✓ **Settings save calls `LoginService.setEnabled`.**
  - verifier: `grep -n 'LoginService.shared.setEnabled(config.general.startWithWindows)' platforms/macos/src/App/SettingsWindow.swift`
  - evidence: line 279 inside `save()`.

- ✓ **`swift build` succeeds and `swift test` is green.**
  - verifier: `cd platforms/macos && swift build && swift test`
  - evidence:
    ```
    Build complete! (1.69s)
    ...
    Executed 71 tests, with 0 failures (0 unexpected) in 0.017 (0.024) seconds
    ✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
    ```

## Decisions / deviations from spec
无偏离。

## Open questions for Leader
- The `app.icns` is placed in `platforms/macos/Resources/app.icns` for T-MAC-51 to wire via `CFBundleIconFile`.
- No automated unit tests were added for `LoginService` because `SMAppService` requires a signed `.app` bundle to register; behavior was verified by compilation and manual code review.

## Commit
N/A — changes left uncommitted per policy (git mutations require explicit user approval).

## Verdict
PASS

## Checks
- `git diff --check` scoped to touched files: clean (no trailing whitespace).
- `swift build`: passed.
- `swift test`: 71 tests passed, 0 failures.

## Next recommendation
T-MAC-51 (App bundle / `Info.plist` + `CFBundleIconFile` wiring) can now consume `Resources/app.icns`.

## Vendor output (parsed) _(preview 8000/50161 chars; full raw stream in `T-MAC-35-output.log`)_

````
• I need to implement start-at-login for macOS using SMAppService and an app icon script. Let me first read the relevant files to understand the project structure and existing code.

• I’ll read the spec, macOS platform docs, and the relevant Swift files, then implement `LoginService`, the icon script, and the wiring.• Now let me find the AppDelegate and Settings window files to understand where to wire things up.Let me read AppDelegate and SettingsWindow to understand where to wire LoginService.Now I understand the structure. I need to:

  1. Create `LoginService.swift` in `platforms/macos/src/App/`
  2. Create `platforms/macos/scripts/build-icon.sh`
  3. Wire `LoginService` in `AppDelegate.swift` (apply on launch + on settings change)
  4. Wire `LoginService` in `SettingsWindow.swift` (toggle calls `LoginService.setEnabled`)
  5. Run `swift build` and `swift test`

  Let me check the Package.swift to understand the module structure.Good. Now let me create the LoginService.swift file. I need to import ServiceManagement for SMAppService. The service should:

  - `setEnabled(_ on: Bool)` → register/unregister
  - `isEnabled() -> Bool` → query status
  - Guard macOS 13+

  Then I'll create the build-icon.sh script, wire it into AppDelegate and SettingsWindow.

  Let me also check if there are any existing tests I need to make sure pass.Now let me create the files. First LoginService.swift.Now create the build-icon.sh script. It needs to render the "文" glyph to PNGs at standard iconset resolutions and then use iconutil to create app.icns.

  Standard iconset sizes:
  - 16x16, 16x16@2x (32x32)
  - 32x32, 32x32@2x (64x64)
  - 128x128, 128x128@2x (256x256)
  - 256x256, 256x256@2x (512x512)
  - 512x512, 512x512@2x (1024x1024)

  I'll use a shell script with `sips` or ImageMagick if available, but it's safer to use `swift` script or `iconutil` with a generic renderer. Actually, the task says "render the single glyph to PNGs". A robust approach on macOS is to use `swift` with CoreGraphics/AppKit to render the glyph. But shell scripts can't easily run Swift inline... well, they can via `swift -e`.

  Alternatively, use `sips` with a base image. But the simplest is to use a Swift one-liner or Python with Pillow. Since this is a macOS project, I'll use a shell script that checks for available tools and prefers `swift`/`AppKit` rendering.

  Actually, the cleanest approach for a build script on macOS is to use a Swift script. But the spec asks for `platforms/macos/scripts/build-icon.sh`. So it should be a bash script. Let me create a bash script that uses ImageMagick's `convert` if available, or `python3` with PIL as fallback, or a Swift inline script. 

  Since we want it to be deterministic and work without external deps, I'll use a Swift inline script invoked from bash. Let me write a bash script that generates the iconset using a Swift helper.

  Actually, let me keep it simpler. I'll write a bash script that uses `sips` to create the iconset from a single rendered PNG. But first we need to render the glyph. I can use `swift` with a heredoc to render the glyph.

  Let me create a script that:
  1. Creates a temporary Swift script to render the glyph at a given size
  2. Runs it for each needed size
  3. Assembles the iconset
  4. Runs `iconutil -c icns`

  Here's the approach:

  ```bash
  #!/bin/bash
  set -euo pipefail

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  ICONSET_DIR="$SCRIPT_DIR/../Resources/app.iconset"
  OUTPUT_ICNS="$SCRIPT_DIR/../Resources/app.icns"

  mkdir -p "$ICONSET_DIR"

  render_size() {
      local size=$1
      local output=$2
      swift - <<'SWIFT'
  import AppKit
  let size = Int(ProcessInfo.processInfo.environment["ICON_SIZE"]!)!
  let output = ProcessInfo.processInfo.environment["ICON_OUTPUT"]!
  let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
      let font = NSFont.systemFont(ofSize: CGFloat(size) * 0.65, weight: .medium)
      let attrs: [NSAttributedString.Key: Any] = [
          .font: font,
          .foregroundColor: NSColor.black
      ]
      let str = NSAttributedString(string: "文", attributes: attrs)
      let strSize = str.size()
      let point = NSPoint(
          x: (rect.width - strSize.width) / 2,
          y: (rect.height - strSize.height) / 2
      )
      str.draw(at: point)
      return true
  }
  guard let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:]) else {
      fatalError("Failed to render icon at \(size)")
  }
  try data.write(to: URL(fileURLWithPath: output))
  SWIFT
  }

  # Render sizes
  for size in 16 32 128 256 512; do
      render_size $size "$ICONSET_DIR/icon_${size}x${size}.png"
  done

  # Generate @2x from the next size up using sips
  sips -z 32 32 "$ICONSET_DIR/icon_32x32.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 64 64 "$ICONSET_DIR/icon_128x128.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 256 256 "$ICONSET_DIR/icon_256x256.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 512 512 "$ICONSET_DIR/icon_512x512.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  # 512@2x needs 1024x1024
  render_size 1024 "$ICONSET_DIR/icon_512x512@2x.png"

  iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
  rm -rf "$ICONSET_DIR"
  ```

  Wait, this is getting complex with the environment variables and swift heredoc. Also, swift heredoc reading environment variables may have issues.

  Let me simplify. I'll create a standalone Swift script file and have the bash script call it. Or better, use a single shell script with `swift` running an inline script but with arguments.

  Actually, let me write the bash script that calls `swift` with a here-doc but uses command-line arguments via `ProcessInfo`. That's cleaner.

  Actually, even simpler: use `swift` with a temporary script file. The bash script creates a temp Swift file, compiles/runs it for each size, then cleans up.

  But maybe the simplest reliable method is to use `python3` with `Pillow`. However, Pillow may not be installed.

  The most reliable on macOS is `sips` + a base image. But we need to create the base image first.

  Let me think about what's in the environment. Since this is macOS, `swift` is available. Let me write a Swift script that takes two arguments (size and output path) and renders the glyph. The bash script calls this Swift script for each size.

  Actually, the spec says "a script `platforms/macos/scripts/build-icon.sh` that renders the single glyph...". So one script. I can embed a Swift helper in the bash script using a heredoc.

  Let me write it carefully. I'll use a here-doc to create a temporary Swift file, run it with size/output args, and then clean it up.

  Let me also check the platforms/macos directory structure for Resources.platforms/macos
platforms/macos/.build
platforms/macos/.build/artifacts
platforms/macos/.build/checkouts
platforms/macos/.build/repositories
platforms/macos/.build/arm64-apple-macosx
platforms/macos/.build/arm64-apple-macosx/debug
platforms/macos/tests
platforms/macos/tests/Conformance
platforms/macos/src
platforms/macos/src/Core
platforms/macos/src/App
No Resources directory yet. The spec says the `.icns` is bundled into the `.app` via `Info.plist` `CFBundleIconFile` in M4 / T-MAC-51; here just produce the `.icns` + the script. So I should put the generated `app.icns` somewhere in platforms/macos. Let me put it in `platforms/macos/Resources/app.icns` and have the script create that directory.

  Now let me write the build-icon.sh script. I'll use a Swift helper script approach.Now I'll write the build-icon.sh script. I need to be careful with the Swift heredoc and argument passing. Let me use a temporary Swift script file approach.

  Actually, the simplest robust way is to have the bash script write a temporary Swift f

... [truncated, 42161 chars omitted]
````

## Status (background completion)
- queue_status: done
- adapter_status: success
- exit_code: 0
- duration_ms: 213598
- end_time: 2026-06-18T06:02:15.925Z
- log: see `T-MAC-35-output.log` for raw output

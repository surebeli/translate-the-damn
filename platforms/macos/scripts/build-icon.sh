#!/bin/bash
# Builds platforms/macos/Resources/app.icns from the shared app glyph: a bold white "T" in a filled
# green circle (#2EA043) — aligned with the Windows app icon (platforms/windows/.../UI/AppIcon.cs).
# Uses AppKit/Swift to render each resolution, then iconutil to assemble the .icns.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="${SCRIPT_DIR}/../Resources"
ICONSET_DIR="${RESOURCES_DIR}/app.iconset"
OUTPUT_ICNS="${RESOURCES_DIR}/app.icns"

mkdir -p "${RESOURCES_DIR}"
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

SWIFT_HELPER="$(mktemp /tmp/build-icon.XXXXXX.swift)"
trap 'rm -f "${SWIFT_HELPER}"' EXIT

cat > "${SWIFT_HELPER}" <<'SWIFT'
import AppKit
let arguments = CommandLine.arguments
let size = Int(arguments[1])!
let output = arguments[2]
let scale = CGFloat(size)
let image = NSImage(size: NSSize(width: scale, height: scale), flipped: false) { rect in
    // Match the Windows app glyph (UI/AppIcon.cs Draw(on:true)): bold white "T" in a green circle.
    NSColor(srgbRed: 46.0 / 255, green: 160.0 / 255, blue: 67.0 / 255, alpha: 1).setFill()
    NSBezierPath(ovalIn: rect).fill()
    let fontSize = scale * 0.6
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let str = NSAttributedString(string: "T", attributes: attrs)
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
    fputs("Failed to render icon at \(size)\n", stderr)
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: output))
} catch {
    fputs("Failed to write \(output): \(error.localizedDescription)\n", stderr)
    exit(1)
}
SWIFT

render() {
    local size="$1"
    local out="$2"
    swift "${SWIFT_HELPER}" "${size}" "${out}"
}

# Render base 1x sizes.
render 16  "${ICONSET_DIR}/icon_16x16.png"
render 32  "${ICONSET_DIR}/icon_32x32.png"
render 128 "${ICONSET_DIR}/icon_128x128.png"
render 256 "${ICONSET_DIR}/icon_256x256.png"
render 512 "${ICONSET_DIR}/icon_512x512.png"

# Derive @2x assets from the next resolution up via sips.
sips -z 32 32   "${ICONSET_DIR}/icon_32x32.png"   --out "${ICONSET_DIR}/icon_16x16@2x.png"   >/dev/null 2>&1
sips -z 64 64   "${ICONSET_DIR}/icon_128x128.png" --out "${ICONSET_DIR}/icon_32x32@2x.png"   >/dev/null 2>&1
sips -z 256 256 "${ICONSET_DIR}/icon_256x256.png" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null 2>&1
sips -z 512 512 "${ICONSET_DIR}/icon_512x512.png" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null 2>&1

# 512x512@2x is 1024x1024.
render 1024 "${ICONSET_DIR}/icon_512x512@2x.png"

# Assemble the .icns and clean up the iconset bundle.
iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_ICNS}"
rm -rf "${ICONSET_DIR}"

echo "Generated ${OUTPUT_ICNS}"

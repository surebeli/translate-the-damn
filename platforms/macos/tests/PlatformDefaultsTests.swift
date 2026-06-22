import XCTest
@testable import TranslateTheDamnCore

/// Per-platform default translate hotkey — the forcing function for a PER-PLATFORM choice.
///
/// `hotkey.translate` is deliberately NOT a shared conformance vector (see the doc in
/// `conformance/config-defaults.json`: "Do not re-pin it" — Win: Shift+Alt+C; macOS: its own). So the
/// Windows runner pins Shift+Alt+C in its own suite, and macOS pins ITS default here, so the value
/// can't silently drift. The string is in shared Windows naming (Law 5); `CarbonKeyMap` maps
/// Ctrl→⌘ and Shift→⇧ at registration, so "Ctrl+Shift+C" is what a Mac user presses as ⇧⌘C
/// (Shift+Command+C) — same mnemonic letter C as Windows, native ⌘-based feel.
final class PlatformDefaultsTests: XCTestCase {
    func testMacOSDefaultTranslateHotkeyString() {
        XCTAssertEqual(ConfigService.defaultConfig().hotkey.translate, "Ctrl+Shift+C",
                       "macOS default translate hotkey string (registers as ⇧⌘C / Shift+Command+C)")
    }

    func testMacOSDefaultHotkeyRegistersAsShiftCommandC() {
        let parsed = HotkeyParser.parse("Ctrl+Shift+C")
        XCTAssertTrue(parsed.isValid, "Ctrl+Shift+C parses")
        XCTAssertEqual(parsed.virtualKey, 0x43, "key = C (VK 0x43)")
        let mods = CarbonKeyMap.carbonModifiers(hasControl: parsed.hasControl, hasAlt: parsed.hasAlt,
                                                hasShift: parsed.hasShift, hasWin: parsed.hasWin)
        XCTAssertEqual(mods, 0x0100 | 0x0200, "Carbon modifiers = ⌘|⇧ (cmdKey|shiftKey) → ⇧⌘C")
    }
}

import Foundation

public enum CarbonKeyMap {

    private static let vkToCarbon: [Int: UInt32] = [
        65: 0x00, 66: 0x0B, 67: 0x08, 68: 0x02, 69: 0x0E,
        70: 0x03, 71: 0x05, 72: 0x04, 73: 0x22, 74: 0x26,
        75: 0x28, 76: 0x25, 77: 0x2E, 78: 0x2D, 79: 0x1F,
        80: 0x23, 81: 0x0C, 82: 0x0F, 83: 0x01, 84: 0x11,
        85: 0x20, 86: 0x09, 87: 0x0D, 88: 0x07, 89: 0x10,
        90: 0x06,

        48: 0x1D, 49: 0x12, 50: 0x13, 51: 0x14, 52: 0x15,
        53: 0x16, 54: 0x17, 55: 0x18, 56: 0x19, 57: 0x1A,

        112: 0x7A, 113: 0x78, 114: 0x63, 115: 0x76, 116: 0x60,
        117: 0x61, 118: 0x62, 119: 0x64, 120: 0x65, 121: 0x6D,
        122: 0x67, 123: 0x6F, 124: 0x69, 125: 0x6B, 126: 0x71,
        127: 0x6A, 128: 0x40, 129: 0x4F, 130: 0x50, 131: 0x5A,

        32: 0x31,
        9: 0x30,
        13: 0x24,
        8: 0x33,
        27: 0x35,
        46: 0x75,
        37: 0x7B,
        38: 0x7E,
        39: 0x7C,
        40: 0x7D,
    ]

    public static func carbonKeyCode(fromVK vk: Int) -> UInt32? {
        return vkToCarbon[vk]
    }

    public static func carbonModifiers(hasControl: Bool, hasAlt: Bool, hasShift: Bool, hasWin: Bool) -> UInt32 {
        var mods: UInt32 = 0
        // macOS porting convention: Windows Ctrl → macOS ⌘ Command (0x0100);
        // Windows Win → macOS ⌃ Control (0x1000). This makes "Ctrl+Alt+T" register as
        // ⌘⌥T (Command+Option+T) — the Mac-appropriate hotkey — while the config/display
        // string stays "Ctrl+Alt+T" (shared schema, Law 4).
        if hasControl { mods |= 0x0100 }  // cmdKey (Ctrl→⌘)
        if hasAlt     { mods |= 0x0800 }  // optionKey (Alt→⌥)
        if hasShift   { mods |= 0x0200 }  // shiftKey (Shift→⇧)
        if hasWin     { mods |= 0x0100 }  // cmdKey (Win/Command→⌘)
        return mods
    }
}

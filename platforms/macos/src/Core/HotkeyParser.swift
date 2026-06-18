import Foundation

/// A parsed global hotkey. `virtualKey` is the **Win32 VK code** (Constitution Law 5: the hotkey
/// parse result must match cross-platform — 'T'=84, F2=113, Space=32). The macOS App layer maps the
/// VK code to a Carbon key code at registration time; the parse itself is platform-neutral.
public struct HotkeyResult: Equatable {
    public var isValid: Bool
    public var hasControl: Bool
    public var hasAlt: Bool
    public var hasWin: Bool
    public var hasShift: Bool
    public var virtualKey: Int
    public var display: String

    public init(
        isValid: Bool = false,
        hasControl: Bool = false,
        hasAlt: Bool = false,
        hasWin: Bool = false,
        hasShift: Bool = false,
        virtualKey: Int = 0,
        display: String = ""
    ) {
        self.isValid = isValid
        self.hasControl = hasControl
        self.hasAlt = hasAlt
        self.hasWin = hasWin
        self.hasShift = hasShift
        self.virtualKey = virtualKey
        self.display = display
    }
}

/// Parses a human hotkey string like "Ctrl+Alt+T" into modifier flags + a virtual key.
public enum HotkeyParser {
    public static func parse(_ text: String) -> HotkeyResult {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return HotkeyResult() }

        let tokens = trimmed.split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard !tokens.isEmpty else { return HotkeyResult() }

        var hasControl = false
        var hasAlt = false
        var hasWin = false
        var hasShift = false
        var keyToken: String? = nil

        for token in tokens {
            switch token {
            case "ctrl", "control": hasControl = true
            case "alt":             hasAlt = true
            case "win", "super", "command", "cmd": hasWin = true
            case "shift":           hasShift = true
            default:
                if keyToken != nil { return HotkeyResult() }
                keyToken = token
            }
        }

        guard let keyToken = keyToken, hasControl || hasAlt || hasWin || hasShift else {
            return HotkeyResult()
        }

        let vk: Int
        let displayKey: String

        if keyToken == "space" {
            vk = 32
            displayKey = "Space"
        } else if let digit = Int(keyToken), (0...9).contains(digit) {
            vk = 48 + digit
            displayKey = keyToken
        } else if keyToken.hasPrefix("f"), let num = Int(keyToken.dropFirst()), (1...24).contains(num) {
            vk = 111 + num
            displayKey = "F\(num)"
        } else if keyToken.count == 1, let char = keyToken.first, char.isLetter {
            let upper = String(char).uppercased()
            vk = Int(upper.unicodeScalars.first?.value ?? 0)
            displayKey = upper
        } else {
            return HotkeyResult()
        }

        var mods: [String] = []
        if hasControl { mods.append("Ctrl") }
        if hasAlt     { mods.append("Alt") }
        if hasShift   { mods.append("Shift") }
        if hasWin     { mods.append("Win") }

        let display = (mods + [displayKey]).joined(separator: "+")

        return HotkeyResult(
            isValid: true,
            hasControl: hasControl,
            hasAlt: hasAlt,
            hasWin: hasWin,
            hasShift: hasShift,
            virtualKey: vk,
            display: display
        )
    }
}

using System.Text;

namespace TranslateTheDamn.Core.Util;

/// <summary>A parsed global hotkey: Win32 modifier flags + virtual-key code for RegisterHotKey.</summary>
public sealed record HotkeySpec(uint Modifiers, uint VirtualKey, bool IsValid, string Display, string? Error)
{
    public static HotkeySpec Invalid(string error) => new(0, 0, false, string.Empty, error);
}

/// <summary>
/// Parses a human hotkey string like "Ctrl+Alt+T" into RegisterHotKey modifier flags + a virtual
/// key. Pure and unit-tested; the App layer feeds the result to RegisterHotKey.
/// </summary>
public static class HotkeyParser
{
    public const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_SHIFT = 0x4, MOD_WIN = 0x8, MOD_NOREPEAT = 0x4000;

    public static HotkeySpec Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return HotkeySpec.Invalid("未设置热键");

        uint mods = 0;
        string? keyName = null;
        foreach (var part in text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            switch (part.ToLowerInvariant())
            {
                case "ctrl": case "control": mods |= MOD_CONTROL; break;
                case "alt": mods |= MOD_ALT; break;
                case "shift": mods |= MOD_SHIFT; break;
                case "win": case "super": case "meta": case "cmd": mods |= MOD_WIN; break;
                default: keyName = part; break;
            }
        }

        if (keyName is null) return HotkeySpec.Invalid("缺少主键");
        var vk = KeyToVk(keyName);
        if (vk == 0) return HotkeySpec.Invalid($"无法识别的按键 “{keyName}”");
        if (mods == 0) return HotkeySpec.Invalid("至少需要一个修饰键(Ctrl/Alt/Shift/Win)");

        return new HotkeySpec(mods | MOD_NOREPEAT, vk, true, BuildDisplay(mods, keyName), null);
    }

    private static uint KeyToVk(string key)
    {
        key = key.Trim();
        if (key.Length == 1)
        {
            char c = char.ToUpperInvariant(key[0]);
            if (c is >= 'A' and <= 'Z') return c;
            if (c is >= '0' and <= '9') return c;
        }
        if (key.Length >= 2 && (key[0] is 'F' or 'f') && int.TryParse(key.AsSpan(1), out var n) && n is >= 1 and <= 24)
            return (uint)(0x70 + (n - 1)); // VK_F1 = 0x70

        return key.ToLowerInvariant() switch
        {
            "space" => 0x20,
            "enter" or "return" => 0x0D,
            "tab" => 0x09,
            "esc" or "escape" => 0x1B,
            "insert" or "ins" => 0x2D,
            "delete" or "del" => 0x2E,
            "home" => 0x24,
            "end" => 0x23,
            "pageup" or "pgup" => 0x21,
            "pagedown" or "pgdn" => 0x22,
            "up" => 0x26,
            "down" => 0x28,
            "left" => 0x25,
            "right" => 0x27,
            _ => 0
        };
    }

    private static string BuildDisplay(uint mods, string key)
    {
        var sb = new StringBuilder();
        if ((mods & MOD_CONTROL) != 0) sb.Append("Ctrl+");
        if ((mods & MOD_ALT) != 0) sb.Append("Alt+");
        if ((mods & MOD_SHIFT) != 0) sb.Append("Shift+");
        if ((mods & MOD_WIN) != 0) sb.Append("Win+");
        sb.Append(key.Length == 1 ? char.ToUpperInvariant(key[0]).ToString() : Capitalize(key));
        return sb.ToString();
    }

    private static string Capitalize(string s) =>
        s.Length == 0 ? s : char.ToUpperInvariant(s[0]) + s[1..].ToLowerInvariant();
}

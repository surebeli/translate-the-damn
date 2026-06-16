using System.Text;

namespace TranslateTheDamn.Core.Util;

/// <summary>
/// Removes ANSI escape sequences (CSI cursor/SGR colour codes + OSC) and carriage returns from
/// captured CLI output. Implemented as a manual scanner to avoid regex-escaping pitfalls.
/// </summary>
public static class AnsiStripper
{
    private const char Esc = (char)0x1B;   // ESC
    private const char Bel = (char)0x07;   // BEL

    public static string Strip(string? s)
    {
        if (string.IsNullOrEmpty(s)) return string.Empty;

        var sb = new StringBuilder(s.Length);
        int i = 0;
        while (i < s.Length)
        {
            char c = s[i];

            if (c == Esc && i + 1 < s.Length)
            {
                char next = s[i + 1];
                if (next == '[')
                {
                    // CSI: ESC '[' params... final-byte in 0x40..0x7E
                    i += 2;
                    while (i < s.Length && (s[i] < '@' || s[i] > '~')) i++;
                    if (i < s.Length) i++; // consume final byte
                    continue;
                }
                if (next == ']')
                {
                    // OSC: ESC ']' ... terminated by BEL or by ST (ESC '\')
                    i += 2;
                    while (i < s.Length && s[i] != Bel && !(s[i] == Esc && i + 1 < s.Length && s[i + 1] == '\\')) i++;
                    if (i < s.Length && s[i] == Bel) i++;
                    else if (i + 1 < s.Length) i += 2; // skip ESC '\'
                    continue;
                }
                // Any other escape: drop ESC + the following byte.
                i += 2;
                continue;
            }

            if (c == '\r') { i++; continue; }

            sb.Append(c);
            i++;
        }

        return sb.ToString();
    }
}

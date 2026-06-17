using System.Text.Json;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Tests;

/// <summary>
/// Windows (reference) runner for the language-neutral conformance vectors in <c>/conformance</c>.
/// Feeds each case through the REAL Core implementation and asserts the expected output, so the
/// Windows column actually satisfies the shared vectors (Constitution Law 2). macOS/Linux add their
/// own runner over the same JSON.
/// </summary>
public static class Conformance
{
    private static readonly string Esc = ((char)0x1B).ToString();

    public static void Run()
    {
        var dir = FindUp("conformance");
        if (dir is null) { Check.True(false, "conformance/ directory located"); return; }

        Each(dir, "prompt-builder.json", (name, input, expected) =>
        {
            var r = PromptBuilder.Build(input.GetProperty("template").GetString()!, input.GetProperty("content").GetString()!);
            Check.Eq(expected.GetString(), r, $"conformance prompt-builder [{name}]");
        });

        Each(dir, "ansi-stripper.json", (name, input, expected) =>
        {
            var s = Markers(input.GetProperty("s").GetString());
            Check.Eq(expected.GetString(), AnsiStripper.Strip(s), $"conformance ansi-stripper [{name}]");
        });

        Each(dir, "hotkey-parser.json", (name, input, expected) =>
        {
            var spec = HotkeyParser.Parse(input.GetProperty("text").GetString());
            Check.Eq(expected.GetProperty("isValid").GetBoolean(), spec.IsValid, $"conformance hotkey [{name}]: isValid");
            if (expected.TryGetProperty("virtualKey", out var vk))
                Check.Eq((uint)vk.GetInt32(), spec.VirtualKey, $"conformance hotkey [{name}]: virtualKey");
            if (expected.TryGetProperty("display", out var disp))
                Check.Eq(disp.GetString(), spec.Display, $"conformance hotkey [{name}]: display");
            if (Flag(expected, "hasControl")) Check.True((spec.Modifiers & HotkeyParser.MOD_CONTROL) != 0, $"conformance hotkey [{name}]: Control");
            if (Flag(expected, "hasAlt")) Check.True((spec.Modifiers & HotkeyParser.MOD_ALT) != 0, $"conformance hotkey [{name}]: Alt");
            if (Flag(expected, "hasShift")) Check.True((spec.Modifiers & HotkeyParser.MOD_SHIFT) != 0, $"conformance hotkey [{name}]: Shift");
            if (Flag(expected, "hasWin")) Check.True((spec.Modifiers & HotkeyParser.MOD_WIN) != 0, $"conformance hotkey [{name}]: Win");
        });
    }

    private static bool Flag(JsonElement obj, string name) =>
        obj.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;

    // Vectors use printable markers for control chars so the JSON stays valid + portable.
    private static string Markers(string? s) =>
        (s ?? string.Empty).Replace("<ESC>", Esc).Replace("<CR>", "\r");

    private static void Each(string dir, string file, Action<string, JsonElement, JsonElement> run)
    {
        var path = Path.Combine(dir, file);
        if (!File.Exists(path)) { Check.True(false, "conformance file exists: " + file); return; }
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        foreach (var c in doc.RootElement.GetProperty("cases").EnumerateArray())
            run(c.GetProperty("name").GetString() ?? "?", c.GetProperty("in"), c.GetProperty("out"));
    }

    private static string? FindUp(string dirName)
    {
        var d = new DirectoryInfo(AppContext.BaseDirectory);
        while (d is not null)
        {
            var candidate = Path.Combine(d.FullName, dirName);
            if (Directory.Exists(candidate)) return candidate;
            d = d.Parent;
        }
        return null;
    }
}

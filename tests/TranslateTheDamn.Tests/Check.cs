namespace TranslateTheDamn.Tests;

/// <summary>Tiny dependency-free assertion harness (nuget.org is unavailable in this environment).</summary>
public static class Check
{
    public static int Passed;
    public static int Failed;
    public static readonly List<string> Failures = new();

    public static void True(bool cond, string name)
    {
        if (cond) Passed++;
        else { Failed++; Failures.Add("FAIL: " + name); }
    }

    public static void Eq<T>(T expected, T actual, string name)
    {
        if (EqualityComparer<T>.Default.Equals(expected, actual)) Passed++;
        else { Failed++; Failures.Add($"FAIL: {name}\n   expected: [{expected}]\n   actual:   [{actual}]"); }
    }

    public static void Contains(string? haystack, string needle, string name)
        => True(haystack is not null && haystack.Contains(needle, StringComparison.Ordinal), $"{name} — contains \"{needle}\"");

    public static void NotContains(string? haystack, string needle, string name)
        => True(haystack is not null && !haystack.Contains(needle, StringComparison.Ordinal), $"{name} — must NOT contain \"{needle}\"");

    public static void SeqContains(IReadOnlyList<string> args, string token, string name)
        => True(args.Contains(token), $"{name} — argv contains \"{token}\"");

    public static void Section(string s) => Console.WriteLine($"\n# {s}");

    public static int Report()
    {
        Console.WriteLine($"\n==================== {Passed} passed, {Failed} failed ====================");
        foreach (var f in Failures) Console.WriteLine(f);
        return Failed == 0 ? 0 : 1;
    }
}

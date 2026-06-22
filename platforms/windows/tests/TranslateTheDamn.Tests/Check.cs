namespace TranslateTheDamn.Tests;

/// <summary>Tiny dependency-free assertion harness (nuget.org is unavailable in this environment).</summary>
public static class Check
{
    public static int Passed;
    public static int Failed;
    public static readonly List<string> Failures = new();

    // --- per-vector result tracking (mechanism #9: emit which conformance vectors actually passed,
    // so scripts/parity-verify.py can cross-check PARITY's Windows column against reality). A vector
    // is green iff no assertion failed while it was the "current" vector. Inert unless Vector() is
    // called, so the non-conformance sections above are never tracked.
    private static string? _currentVector;
    public static readonly Dictionary<string, bool> VectorOk = new();

    /// <summary>Begin attributing subsequent assertions to conformance vector <paramref name="stem"/>
    /// (the JSON filename without extension). Pass null to stop attributing.</summary>
    public static void Vector(string? stem)
    {
        _currentVector = stem;
        if (stem is not null && !VectorOk.ContainsKey(stem)) VectorOk[stem] = true;
    }

    private static void MarkFail()
    {
        Failed++;
        if (_currentVector is not null) VectorOk[_currentVector] = false;
    }

    public static void True(bool cond, string name)
    {
        if (cond) Passed++;
        else { MarkFail(); Failures.Add("FAIL: " + name); }
    }

    public static void Eq<T>(T expected, T actual, string name)
    {
        if (EqualityComparer<T>.Default.Equals(expected, actual)) Passed++;
        else { MarkFail(); Failures.Add($"FAIL: {name}\n   expected: [{expected}]\n   actual:   [{actual}]"); }
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

    /// <summary>Emit per-vector results JSON for scripts/parity-verify.py. Dependency-free
    /// serialization (the harness uses no external JSON writer). Called only when the runner is asked
    /// to emit (TTD_EMIT_RESULTS set).</summary>
    public static void WriteResults(string path)
    {
        var sb = new System.Text.StringBuilder();
        sb.Append("{\n  \"platform\": \"windows\",\n  \"vectors\": {");
        var first = true;
        foreach (var kv in VectorOk)
        {
            sb.Append(first ? "\n" : ",\n");
            first = false;
            sb.Append($"    \"{kv.Key}\": {(kv.Value ? "true" : "false")}");
        }
        sb.Append(first ? "}\n}\n" : "\n  }\n}\n");
        File.WriteAllText(path, sb.ToString());
        Console.Error.WriteLine($"conformance-results → {path} ({VectorOk.Count} vectors)");
    }
}

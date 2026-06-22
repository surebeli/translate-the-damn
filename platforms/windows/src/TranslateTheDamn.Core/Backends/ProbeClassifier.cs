using System.Text;

namespace TranslateTheDamn.Core.Backends;

/// <summary>Outcome of an auth/connectivity probe.</summary>
public enum ProbeStatus { Ok, Fail, Unknown }

/// <summary>
/// Generic auth/connectivity classifier shared by the doctor and the CLI translator (spec §6,
/// conformance <c>doctor-classify</c>). Normalizes both the probe output and each signature
/// (lowercase + strip ALL whitespace), then applies <b>SUCCESS-WINS</b>:
/// <list type="bullet">
/// <item>ok if any <c>successSignature</c> is present;</item>
/// <item>else fail if any <c>failSignature</c> is present;</item>
/// <item>else unknown.</item>
/// </list>
/// Success-wins is what makes the agy keyring transient — a log with "not logged into Antigravity"
/// <em>followed by</em> a success marker — classify as <c>ok</c> (not a logout), and it fixes the
/// matching false-<c>AuthFail</c> in <see cref="ProcessTranslator"/>. Whitespace stripping makes the
/// match robust to compact-vs-pretty JSON and the codex "not logged in" ⊄ "logged in using" trap.
/// </summary>
public static class ProbeClassifier
{
    public static ProbeStatus Classify(IReadOnlyList<string>? success, IReadOnlyList<string>? fail, string text, bool failWins = false)
    {
        var hay = Normalize(text);
        if (failWins)
        {
            // Fail-wins: a fail marker beats a success substring (opencode "credentials" ⊂ "0 credentials").
            if (HasAny(fail, hay)) return ProbeStatus.Fail;
            if (HasAny(success, hay)) return ProbeStatus.Ok;
            return ProbeStatus.Unknown;
        }
        // Success-wins (default): a success marker beats a transient fail (agy keyring "not logged in").
        if (HasAny(success, hay)) return ProbeStatus.Ok;
        if (HasAny(fail, hay)) return ProbeStatus.Fail;
        return ProbeStatus.Unknown;
    }

    /// <summary>True if any signature (normalized) is a substring of the already-normalized text.</summary>
    public static bool HasAny(IReadOnlyList<string>? signatures, string normalizedText)
    {
        if (signatures is null) return false;
        foreach (var s in signatures)
        {
            var n = Normalize(s);
            if (n.Length > 0 && normalizedText.Contains(n, StringComparison.Ordinal)) return true;
        }
        return false;
    }

    /// <summary>Lowercase + strip all whitespace.</summary>
    public static string Normalize(string? s)
    {
        if (string.IsNullOrEmpty(s)) return string.Empty;
        var sb = new StringBuilder(s.Length);
        foreach (var ch in s)
            if (!char.IsWhiteSpace(ch)) sb.Append(char.ToLowerInvariant(ch));
        return sb.ToString();
    }
}

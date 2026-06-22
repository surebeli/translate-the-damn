using System.Text.Json;

namespace TranslateTheDamn.Core.Config;

/// <summary>A STATIC API credential discovered on the local machine, ready to import as an http backend.
/// The <see cref="Key"/> is the real secret — never log it; the UI shows <see cref="KeyMasked"/>.</summary>
public sealed record DiscoveredCredential(
    string Source,       // provenance, e.g. "env:DEEPSEEK_API_KEY" or a config file path
    string Provider,     // display name, e.g. "DeepSeek"
    string SuggestedId,  // backend id to create, e.g. "deepseek"
    string BaseUrl,      // canonical base (chat suffix stripped), e.g. "https://api.deepseek.com/v1"
    string Protocol,     // "openai" | "anthropic"
    string KeyMasked,    // prefix + length for the UI, e.g. "sk-d2fd…(35)"
    string Key);         // the actual secret — NEVER log / telemetry

/// <summary>Pure classifier: turns a (source, baseUrl, key) tuple into an importable credential, or null
/// to SKIP. The static-key/OAuth boundary is the security contract — pinned by conformance/credential-discovery.json.</summary>
public static class CredentialClassifier
{
    // Hard-skip hosts: subscription OAuth / first-party that must NOT be scraped (ToS bans + token churn).
    private static readonly string[] SubscriptionHosts =
    {
        "api.anthropic.com", "claude.ai",
        "generativelanguage.googleapis.com", "cloudcode-pa.googleapis.com", "oauth2.googleapis.com", "accounts.google.com",
        "api.githubcopilot.com", "github.com"
    };

    public static DiscoveredCredential? Classify(string source, string? baseUrl, string? key)
    {
        if (string.IsNullOrWhiteSpace(key) || string.IsNullOrWhiteSpace(baseUrl)) return null;
        if (LooksLikeOAuthToken(key!)) return null;                       // JWT / refresh / Google / GitHub -> not a static key
        var host = HostOf(baseUrl!);
        if (host is null) return null;
        if (Array.Exists(SubscriptionHosts, h => host == h || host.EndsWith("." + h, StringComparison.Ordinal))) return null;

        var (provider, protocol, id, normBase) = MapHost(host, baseUrl!);
        return new DiscoveredCredential(source, provider, id, normBase, protocol, Mask(key!), key!.Trim());
    }

    /// <summary>True for refreshing/client-bound OAuth tokens that are NOT importable static keys.</summary>
    public static bool LooksLikeOAuthToken(string key)
    {
        var k = key.Trim();
        if (k.Length == 0) return false;
        if (k.StartsWith("eyJ", StringComparison.Ordinal)) return true;   // JWT access_token (Kimi/Codex/Anthropic OAuth)
        if (k.StartsWith("ya29.", StringComparison.Ordinal)) return true; // Google OAuth access_token
        if (k.StartsWith("1//", StringComparison.Ordinal)) return true;   // Google refresh token
        if (k.StartsWith("gho_", StringComparison.Ordinal) || k.StartsWith("ghu_", StringComparison.Ordinal)) return true; // GitHub
        if (k.Length > 300) return true;                                  // OAuth tokens are long; static API keys aren't
        return false;
    }

    private static (string provider, string protocol, string id, string normBase) MapHost(string host, string baseUrl)
    {
        if (host == "api.deepseek.com") return ("DeepSeek", "openai", "deepseek", "https://api.deepseek.com/v1");
        if (host == "api.moonshot.ai" || host == "api.moonshot.cn") return ("Moonshot", "openai", "moonshot", "https://api.moonshot.ai/v1");
        if (host == "api.kimi.com") return ("Kimi Code", "anthropic", "kimi-code", "https://api.kimi.com/coding/v1");
        if (host == "api.xiaomimimo.com") return ("Xiaomi MiMo", "openai", "mimo", "https://api.xiaomimimo.com/v1");
        if (host.EndsWith(".xiaomimimo.com", StringComparison.Ordinal)) return ("Xiaomi MiMo Token-Plan", "openai", "mimo-token-plan", TrimToBase(baseUrl));
        if (host == "tokbox-api.netease.im") return ("tokenbox", "openai", "tokenbox", "https://tokbox-api.netease.im/v1");
        if (host == "openrouter.ai") return ("OpenRouter", "openai", "openrouter", "https://openrouter.ai/api/v1");
        if (host == "api.openai.com") return ("OpenAI", "openai", "openai", "https://api.openai.com/v1");
        // Unknown host: import as a generic OpenAI-compatible provider (user reviews + confirms each import).
        return (host, "openai", host.Replace('.', '-'), TrimToBase(baseUrl));
    }

    private static string TrimToBase(string url)
    {
        var u = url.Trim().TrimEnd('/');
        foreach (var tail in new[] { "/chat/completions", "/messages", "/responses", "/completions" })
            if (u.EndsWith(tail, StringComparison.OrdinalIgnoreCase)) return u[..^tail.Length];
        return u;
    }

    private static string? HostOf(string url)
    {
        try { return new Uri(url.Contains("://", StringComparison.Ordinal) ? url : "https://" + url).Host.ToLowerInvariant(); }
        catch { return null; }
    }

    /// <summary>Prefix + length only — never the full secret.</summary>
    public static string Mask(string key)
    {
        var k = key.Trim();
        return (k.Length <= 8 ? k : k.Substring(0, 8)) + $"…({k.Length})";
    }
}

/// <summary>Read-only scanner: discovers user-owned STATIC keys from env vars + opencode + codex configs
/// (cc-switch SQLite deferred). Never writes; never reads OAuth stores (~/.claude, ~/.gemini, etc.).</summary>
public static class CredentialDiscovery
{
    // Conventional env var -> canonical base URL.
    private static readonly (string env, string baseUrl)[] EnvProviders =
    {
        ("DEEPSEEK_API_KEY",   "https://api.deepseek.com/v1"),
        ("MOONSHOT_API_KEY",   "https://api.moonshot.ai/v1"),
        ("MIMO_API_KEY",       "https://api.xiaomimimo.com/v1"),
        ("OPENROUTER_API_KEY", "https://openrouter.ai/api/v1"),
        ("GROQ_API_KEY",       "https://api.groq.com/openai/v1"),
    };

    // opencode auth.json provider id -> base URL (auth.json stores only the key).
    private static readonly Dictionary<string, string> OpencodeProviderBase = new(StringComparer.OrdinalIgnoreCase)
    {
        ["deepseek"] = "https://api.deepseek.com/v1",
        ["moonshot"] = "https://api.moonshot.ai/v1",
        ["kimi-code"] = "https://api.kimi.com/coding/v1",
        ["xiaomi"] = "https://api.xiaomimimo.com/v1",
        ["xiaomi-token-plan-cn"] = "https://token-plan-cn.xiaomimimo.com/v1",
        ["openrouter"] = "https://openrouter.ai/api/v1",
        ["groq"] = "https://api.groq.com/openai/v1",
    };

    /// <summary>Scan all sources; dedup on (host, key); skip anything that doesn't classify as a static key.</summary>
    public static IReadOnlyList<DiscoveredCredential> Scan(string? home = null)
    {
        var profile = home ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var raw = new List<(string source, string baseUrl, string key)>();
        raw.AddRange(FromEnv());
        raw.AddRange(FromOpencodeAuth(Path.Combine(profile, ".local", "share", "opencode", "auth.json")));
        raw.AddRange(FromOpencodeConfig(Path.Combine(profile, ".config", "opencode", "opencode.json")));
        raw.AddRange(FromCodexToml(Path.Combine(profile, ".codex", "config.toml")));

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var found = new List<DiscoveredCredential>();
        foreach (var (source, baseUrl, key) in raw)
        {
            var c = CredentialClassifier.Classify(source, baseUrl, key);
            if (c is null) continue;
            var dedupKey = HostKey(c.BaseUrl) + "|" + c.Key;
            if (seen.Add(dedupKey)) found.Add(c);
        }
        return found;
    }

    private static string HostKey(string url) { try { return new Uri(url).Host.ToLowerInvariant(); } catch { return url; } }

    private static IEnumerable<(string, string, string)> FromEnv()
    {
        foreach (var (env, baseUrl) in EnvProviders)
        {
            var k = EnvVar(env);
            if (!string.IsNullOrWhiteSpace(k)) yield return ($"env:{env}", baseUrl, k!);
        }
        var ok = EnvVar("OPENAI_API_KEY");
        if (!string.IsNullOrWhiteSpace(ok))
            yield return ("env:OPENAI_API_KEY", EnvVar("OPENAI_BASE_URL") ?? "https://api.openai.com/v1", ok!);
    }

    private static string? EnvVar(string name) =>
        Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.User)
        ?? Environment.GetEnvironmentVariable(name);

    private static IEnumerable<(string, string, string)> FromOpencodeAuth(string path)
    {
        if (!File.Exists(path)) yield break;
        JsonElement root;
        try { using var doc = JsonDocument.Parse(File.ReadAllText(path)); root = doc.RootElement.Clone(); }
        catch { yield break; }
        if (root.ValueKind != JsonValueKind.Object) yield break;
        foreach (var p in root.EnumerateObject())
        {
            if (p.Value.ValueKind != JsonValueKind.Object) continue;
            var type = p.Value.TryGetProperty("type", out var t) ? t.GetString() : null;
            if (!string.Equals(type, "api", StringComparison.OrdinalIgnoreCase)) continue;   // skip oauth entries
            var key = p.Value.TryGetProperty("key", out var k) ? k.GetString() : null;
            if (string.IsNullOrWhiteSpace(key)) continue;
            if (!OpencodeProviderBase.TryGetValue(p.Name, out var baseUrl)) continue;          // unknown provider -> no base, skip
            yield return ($"opencode:auth.json:{p.Name}", baseUrl, key!);
        }
    }

    private static IEnumerable<(string, string, string)> FromOpencodeConfig(string path)
    {
        if (!File.Exists(path)) yield break;
        JsonElement root;
        try { using var doc = JsonDocument.Parse(File.ReadAllText(path)); root = doc.RootElement.Clone(); }
        catch { yield break; }
        if (!root.TryGetProperty("provider", out var provs) || provs.ValueKind != JsonValueKind.Object) yield break;
        foreach (var p in provs.EnumerateObject())
        {
            if (!p.Value.TryGetProperty("options", out var opts) || opts.ValueKind != JsonValueKind.Object) continue;
            var baseUrl = opts.TryGetProperty("baseURL", out var b) ? b.GetString() : null;
            var key = opts.TryGetProperty("apiKey", out var k) ? k.GetString() : null;
            if (string.IsNullOrWhiteSpace(baseUrl) || string.IsNullOrWhiteSpace(key)) continue;
            yield return ($"opencode:opencode.json:{p.Name}", baseUrl!, key!);
        }
    }

    // Minimal line-based reader for codex config.toml [model_providers.<id>] base_url + env_key (the key lives in the named env var).
    private static IEnumerable<(string, string, string)> FromCodexToml(string path)
    {
        if (!File.Exists(path)) yield break;
        string[] lines;
        try { lines = File.ReadAllLines(path); } catch { yield break; }
        string? id = null, baseUrl = null, envKey = null;
        var results = new List<(string, string, string)>();
        void Flush()
        {
            if (id is not null && baseUrl is not null && envKey is not null)
            {
                var key = EnvVar(envKey);
                if (!string.IsNullOrWhiteSpace(key)) results.Add(($"codex:config.toml:{id}", baseUrl!, key!));
            }
            baseUrl = null; envKey = null;
        }
        foreach (var line in lines)
        {
            var t = line.Trim();
            if (t.StartsWith("[", StringComparison.Ordinal))
            {
                Flush();
                id = t.StartsWith("[model_providers.", StringComparison.OrdinalIgnoreCase)
                    ? t.TrimStart('[').TrimEnd(']').Substring("model_providers.".Length).Trim('"')
                    : null;
            }
            else if (id is not null)
            {
                var v = TomlValue(t, "base_url"); if (v is not null) baseUrl = v;
                var e = TomlValue(t, "env_key"); if (e is not null) envKey = e;
            }
        }
        Flush();
        foreach (var r in results) yield return r;
    }

    private static string? TomlValue(string line, string key)
    {
        var t = line.Trim();
        if (!t.StartsWith(key, StringComparison.OrdinalIgnoreCase)) return null;
        var eq = t.IndexOf('=');
        if (eq < 0) return null;
        return t[(eq + 1)..].Trim().Trim('"');
    }
}

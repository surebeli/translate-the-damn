using System.Net.Http;
using System.Text.Json;
using TranslateTheDamn.Core.Backends.Manifest;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends;

/// <summary>
/// Generic, manifest-driven LIVE model enumeration (spec §9). For backends that declare a
/// <c>modelsCmd</c> in <c>spec/backends.json</c> (e.g. opencode/mimo <c>models</c>), it runs that
/// subcommand non-interactively and parses the one-id-per-line output, so the settings model dropdown
/// shows the user's ACTUAL current models instead of a drifting static snapshot. No per-vendor
/// branching (Constitution Law 6). Any failure path (no <c>modelsCmd</c>, binary missing, non-zero,
/// timeout, garbage) returns an empty list so the caller simply keeps the static catalog as fallback.
/// </summary>
public static class ModelEnumerator
{
    private static readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(10) };

    public static async Task<IReadOnlyList<string>> EnumerateAsync(
        string backendId, BackendConfig cfg, ProcessRunner? runner, CancellationToken ct)
    {
        // HTTP/API backends enumerate via the OpenAI/Anthropic-compatible GET /models endpoint.
        if (cfg.Kind == BackendKind.Http)
            return await EnumerateHttpModelsAsync(cfg, ct);

        // CLI backends run the manifest-declared models subcommand.
        var def = BackendManifest.Load().Backends.TryGetValue(backendId, out var d) ? d : null;
        if (def?.ModelsCmd is not { Count: > 0 } modelsArgs) return Array.Empty<string>();

        var command = string.IsNullOrWhiteSpace(cfg.Command) ? (def.Command ?? backendId) : cfg.Command!;
        var known = def.KnownInstallPaths is not null && def.KnownInstallPaths.TryGetValue("windows", out var kp)
            ? kp : (IReadOnlyList<string>)Array.Empty<string>();
        var resolved = PathResolver.Resolve(command, known);
        if (resolved is null) return Array.Empty<string>();

        try
        {
            // Cap at 15s (ceiling, not floor) — enumeration must never hang the settings dialog.
            var ceiling = Math.Clamp(cfg.TimeoutSec * 1000, 3000, 15000);
            var r = await (runner ?? new ProcessRunner())
                .RunAsync(resolved, modelsArgs, StdinMode.Empty, null, ceiling, 0, null, Sandbox.Directory, ct);
            return ParseModels(r.Stdout);
        }
        catch { return Array.Empty<string>(); }
    }

    /// <summary>One model id per line; keep <c>provider/model</c> ids, drop chrome / blank / spaced lines.
    /// Deduped, original order preserved. Pure + public so it can be unit-tested without a process.</summary>
    public static IReadOnlyList<string> ParseModels(string stdout)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var models = new List<string>();
        foreach (var line in AnsiStripper.Strip(stdout).Split('\n'))
        {
            var t = line.Trim();
            if (t.Length == 0 || t.Contains(' ') || !t.Contains('/')) continue;  // model ids are "provider/name", never spaced
            if (seen.Add(t)) models.Add(t);
        }
        return models;
    }

    /// <summary>Enumerate an API backend's models via its OpenAI/Anthropic-compatible <c>GET /models</c>
    /// endpoint (derived from the chat endpoint). Best-effort: any failure returns empty so the caller
    /// keeps the existing catalog. Sends the user's own key to the user's own provider.</summary>
    private static async Task<IReadOnlyList<string>> EnumerateHttpModelsAsync(BackendConfig cfg, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(cfg.Endpoint) || string.IsNullOrWhiteSpace(cfg.ApiKey)) return Array.Empty<string>();
        var anthropic = string.Equals(cfg.Protocol, "anthropic", StringComparison.OrdinalIgnoreCase);
        // Try each candidate /models path until one returns a list (a bare base needs /v1/models, not /models).
        foreach (var url in DeriveModelsUrls(cfg.Endpoint!))
        {
            if (ct.IsCancellationRequested) break;
            try
            {
                using var req = new HttpRequestMessage(HttpMethod.Get, url);
                req.Headers.TryAddWithoutValidation("Authorization", "Bearer " + cfg.ApiKey);  // Bearer works for deepseek/kimi/anthropic relays
                if (anthropic)
                {
                    req.Headers.TryAddWithoutValidation("x-api-key", cfg.ApiKey);
                    req.Headers.TryAddWithoutValidation("anthropic-version", "2023-06-01");
                }
                using var resp = await _http.SendAsync(req, ct);
                if (!resp.IsSuccessStatusCode) continue;
                var models = ParseModelsJson(await resp.Content.ReadAsStringAsync(ct));
                if (models.Count > 0) return models;
            }
            catch { /* try the next candidate */ }
        }
        return Array.Empty<string>();
    }

    /// <summary>First candidate <c>/models</c> URL (kept for the simple cases / existing tests).</summary>
    public static string? DeriveModelsUrl(string endpoint) => DeriveModelsUrls(endpoint).FirstOrDefault();

    /// <summary>Candidate <c>/models</c> URLs for ANY chat/messages/base endpoint, tried in order until
    /// one returns a list. Recovers the API root by stripping a known chat tail, prefers a versioned
    /// <c>/v1/models</c> for a version-less root (relays serve <c>/v1/models</c>, not <c>/models</c>),
    /// and adds authority-root fallbacks. Covers OpenAI, Anthropic, OpenRouter (<c>/api/v1</c>), Gemini
    /// (<c>/v1beta</c>), Ollama, and most relays. Pure + public for tests.</summary>
    public static IReadOnlyList<string> DeriveModelsUrls(string endpoint)
    {
        var urls = new List<string>();
        if (string.IsNullOrWhiteSpace(endpoint)) return urls;
        var e = endpoint.Trim().TrimEnd('/');
        void Add(string u) { if (!string.IsNullOrEmpty(u) && !urls.Contains(u, StringComparer.OrdinalIgnoreCase)) urls.Add(u); }

        // Recover the API root: strip a known chat/models tail (e.g. .../v1/chat/completions -> .../v1).
        var root = e;
        foreach (var tail in new[] { "/chat/completions", "/messages", "/responses", "/completions" })
            if (root.EndsWith(tail, StringComparison.OrdinalIgnoreCase)) { root = root[..^tail.Length]; break; }
        if (root.EndsWith("/models", StringComparison.OrdinalIgnoreCase)) root = root[..^"/models".Length];

        // Prefer a versioned /v1/models for a version-less root.
        var hasVersion = System.Text.RegularExpressions.Regex.IsMatch(root, @"/v\d");
        if (hasVersion) Add(root + "/models");
        else { Add(root + "/v1/models"); Add(root + "/models"); }

        // Authority-root fallbacks (handles odd sub-paths / proxies).
        try { var authority = new Uri(e).GetLeftPart(UriPartial.Authority); Add(authority + "/v1/models"); Add(authority + "/models"); }
        catch { /* not an absolute uri */ }
        return urls;
    }

    /// <summary>Parse a models-list response across the common shapes: OpenAI/Anthropic
    /// <c>{ "data": [ { "id" } ] }</c>, Ollama <c>{ "models": [ { "name" } ] }</c>, or a bare array of
    /// strings/objects (<c>id</c>/<c>name</c>/<c>model</c>). Deduped, order-preserved. Pure + public for tests.</summary>
    public static IReadOnlyList<string> ParseModelsJson(string json)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var ids = new List<string>();
        void TryAdd(string? s) { if (!string.IsNullOrWhiteSpace(s) && seen.Add(s!)) ids.Add(s!); }
        void Scan(JsonElement arr)
        {
            foreach (var m in arr.EnumerateArray())
            {
                if (m.ValueKind == JsonValueKind.String) { TryAdd(m.GetString()); continue; }
                if (m.ValueKind != JsonValueKind.Object) continue;
                if (m.TryGetProperty("id", out var v) && v.ValueKind == JsonValueKind.String) TryAdd(v.GetString());
                else if (m.TryGetProperty("name", out var n) && n.ValueKind == JsonValueKind.String) TryAdd(n.GetString());
                else if (m.TryGetProperty("model", out var md) && md.ValueKind == JsonValueKind.String) TryAdd(md.GetString());
            }
        }
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.ValueKind == JsonValueKind.Array) Scan(root);
            else if (root.ValueKind == JsonValueKind.Object)
                foreach (var key in new[] { "data", "models" })
                    if (root.TryGetProperty(key, out var arr) && arr.ValueKind == JsonValueKind.Array) Scan(arr);
        }
        catch { /* not JSON / unexpected shape -> empty */ }
        return ids;
    }
}

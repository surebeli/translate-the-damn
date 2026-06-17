using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace TranslateTheDamn.Core.Backends.Manifest;

/// <summary>
/// The declarative backend manifest (`spec/backends.json`), embedded into this assembly and read at
/// runtime. It is the single source of truth for HOW each backend is invoked (Constitution Q2); the
/// generic <see cref="ManifestCliBackend"/> / <see cref="ManifestHttpBackend"/> interpret it.
/// </summary>
public sealed class BackendManifest
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
        ReadCommentHandling = JsonCommentHandling.Skip
    };

    private static BackendManifest? _cached;

    public int Schema { get; set; } = 1;
    public Dictionary<string, BackendDef> Backends { get; set; } = new();

    /// <summary>Loads (and caches) the embedded manifest.</summary>
    public static BackendManifest Load()
    {
        if (_cached is not null) return _cached;

        var asm = typeof(BackendManifest).Assembly;
        using var stream = asm.GetManifestResourceStream("backends.json")
            ?? throw new InvalidOperationException("Embedded resource 'backends.json' not found.");
        using var reader = new StreamReader(stream);
        var json = reader.ReadToEnd();

        _cached = JsonSerializer.Deserialize<BackendManifest>(json, Options)
            ?? throw new InvalidOperationException("Failed to parse backends.json.");
        return _cached;
    }
}

public sealed class BackendDef
{
    public string Kind { get; set; } = "cli";

    // --- cli ---
    public string? Command { get; set; }
    public string? PromptVia { get; set; }            // stdin | stdin-dash | arg
    public List<string>? Args { get; set; }
    public ParseRule? Parse { get; set; }
    public string? FallbackCommand { get; set; }
    public List<string>? FallbackArgs { get; set; }
    public Dictionary<string, List<string>>? KnownInstallPaths { get; set; }

    // --- http ---
    public string? Endpoint { get; set; }
    public string? Method { get; set; }
    public Dictionary<string, string>? Headers { get; set; }
    public JsonElement BodyTemplate { get; set; }
    public List<string>? OmitWhenEmpty { get; set; }
    public string? ResponsePath { get; set; }

    // --- shared defaults (model, reasoning, outputFormat, target, format, targetLanguage, timeoutSec…) ---
    public Dictionary<string, JsonElement>? Defaults { get; set; }

    public string? DefaultString(string key) =>
        Defaults is not null && Defaults.TryGetValue(key, out var v)
            ? (v.ValueKind == JsonValueKind.String ? v.GetString() : v.GetRawText())
            : null;

    public int DefaultInt(string key, int fallback) =>
        Defaults is not null && Defaults.TryGetValue(key, out var v) && v.ValueKind == JsonValueKind.Number
            ? v.GetInt32() : fallback;
}

public sealed class ParseRule
{
    public string? Mode { get; set; }
    public string? JsonResultPath { get; set; }
    public string? JsonEvent { get; set; }
    public string? LogDiagnosis { get; set; }
}

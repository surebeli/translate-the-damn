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

        var manifest = JsonSerializer.Deserialize<BackendManifest>(json, Options)
            ?? throw new InvalidOperationException("Failed to parse backends.json.");

        // Look up backends case-insensitively (the registry map is too).
        manifest.Backends = new Dictionary<string, BackendDef>(manifest.Backends, StringComparer.OrdinalIgnoreCase);
        _cached = manifest;
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
    public List<ArgsAppendDef>? ArgsAppend { get; set; }  // conditional extra args (e.g. --effort) appended only when `when` var is non-empty
    public List<string>? EffortTiers { get; set; }        // allowed effort/reasoning tiers for the per-vendor selector
    public ProbeDef? Probe { get; set; }                  // doctor: non-interactive auth/connectivity probe
    public List<string>? ModelsCmd { get; set; }          // live model enumeration subcommand, e.g. ["models"] (opencode/mimo)
    public ParseRule? Parse { get; set; }
    public string? FallbackCommand { get; set; }
    public List<string>? FallbackArgs { get; set; }
    public Dictionary<string, List<string>>? KnownInstallPaths { get; set; }

    // --- http ---
    public string? Endpoint { get; set; }
    public string? ChatPath { get; set; }             // appended to a BASE endpoint if missing (openai:/chat/completions, anthropic:/messages)
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
    // JSONL / stream-json output (opencode, kimi): each stdout line is a JSON object; collect the text
    // of every object whose "type" == JsonlType, read from JsonlTextPath, concatenated in order.
    public bool Jsonl { get; set; }
    public string? JsonlType { get; set; }      // e.g. "text"
    public string? JsonlTextPath { get; set; }  // e.g. "part.text" (opencode) or "text" (kimi)
}

/// <summary>Append <see cref="Args"/> to the argv only when the variable named <see cref="When"/>
/// is non-empty (e.g. claude/copilot <c>--effort {reasoning}</c> only when a tier is selected).</summary>
public sealed class ArgsAppendDef
{
    public string When { get; set; } = string.Empty;
    public List<string> Args { get; set; } = new();
}

/// <summary>Declarative doctor probe: how to check a backend's auth/connectivity non-interactively.
/// <c>Args</c> = run a local auth command (claude/codex); <c>Kind="log"</c> + <c>CredFiles</c> =
/// presence/log check (agy); none = presence-only (copilot).</summary>
public sealed class ProbeDef
{
    public string? Kind { get; set; }                     // null = run Args; "log" = cred-file/log probe
    public List<string>? Args { get; set; }
    public bool Network { get; set; }
    public int Retries { get; set; }
    public bool ExitZeroIsAuth { get; set; }
    public bool FailWins { get; set; }   // evaluate failSignatures FIRST (opencode: "credentials" ⊂ "0 credentials")
    public List<string>? SuccessSignatures { get; set; }
    public List<string>? FailSignatures { get; set; }
    public List<string>? CredFiles { get; set; }
}

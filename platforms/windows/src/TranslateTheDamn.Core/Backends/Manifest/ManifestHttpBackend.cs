using System.Text.Json;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends.Manifest;

/// <summary>
/// Generic HTTP backend driven by a <see cref="BackendDef"/>: builds the request (method/url/headers/
/// body) from the manifest templates (dropping empty <c>omitWhenEmpty</c> keys) and reads the
/// translated text out of the response via <c>responsePath</c> — all from data, no per-backend code.
/// </summary>
public sealed class ManifestHttpBackend : HttpTranslator
{
    private readonly string _id;
    private readonly BackendDef _def;
    private readonly string _promptTemplate;

    public ManifestHttpBackend(string id, BackendDef def, BackendConfig cfg, string promptTemplate = "") : base(cfg)
    {
        _id = id;
        _def = def;
        _promptTemplate = promptTemplate;
    }

    public override string Id => _id;
    protected override bool HasCredential => !string.IsNullOrWhiteSpace(Cfg.ApiKey);

    private string Endpoint
    {
        get
        {
            var e = (string.IsNullOrWhiteSpace(Cfg.Endpoint) ? (_def.Endpoint ?? string.Empty) : Cfg.Endpoint!).Trim();
            // If the manifest declares a chatPath (openai-http/anthropic-http) and the user gave a BASE
            // (e.g. https://host/v1) instead of the full chat URL, append it — matching the @ai-sdk/
            // openai-compatible convention where the configured baseURL omits /chat/completions.
            if (!string.IsNullOrEmpty(_def.ChatPath) && e.Length > 0)
            {
                var trimmed = e.TrimEnd('/');
                if (!trimmed.EndsWith(_def.ChatPath, StringComparison.OrdinalIgnoreCase)) e = trimmed + _def.ChatPath;
            }
            return e;
        }
    }
    private string Method => _def.Method ?? "POST";

    public override HttpCall BuildCall(string text)
    {
        var vars = Vars(text);

        var headers = new Dictionary<string, string>();
        if (_def.Headers is not null)
            foreach (var h in _def.Headers) headers[h.Key] = ManifestEngine.Subst(h.Value, vars);

        var omit = new HashSet<string>(_def.OmitWhenEmpty ?? new List<string>(), StringComparer.Ordinal);
        var body = ManifestEngine.BuildBody(_def.BodyTemplate, vars, omit);
        return new HttpCall(Method, Endpoint, headers, body);
    }

    public override string? ParseResponse(string json)
    {
        if (string.IsNullOrWhiteSpace(_def.ResponsePath)) return null;
        try
        {
            using var doc = JsonDocument.Parse(json);
            return ManifestEngine.Eval(doc.RootElement, _def.ResponsePath!);
        }
        catch { return null; }
    }

    private Dictionary<string, string> Vars(string text) => new(StringComparer.Ordinal)
    {
        ["text"] = text,
        // {prompt} = the full built translation prompt (rules + text), as the CLI backends send. Distinct
        // from PromptBuilder's own {content} placeholder. Unused by google-v2/doubao (they use {text}).
        ["prompt"] = PromptBuilder.Build(_promptTemplate, text),
        ["apiKey"] = Cfg.ApiKey ?? string.Empty,
        ["model"] = Pick(Cfg.Model, "model"),
        ["target"] = Pick(Cfg.Target, "target"),
        ["format"] = Pick(Cfg.Format, "format"),
        ["targetLanguage"] = Pick(Cfg.TargetLanguage, "targetLanguage"),
        ["source"] = Cfg.Source ?? string.Empty,            // empty is valid (omitted) — no default
        ["sourceLanguage"] = Cfg.SourceLanguage ?? string.Empty
    };

    // Config value if non-blank, else the manifest default (an empty string counts as unset).
    private string Pick(string? cfgValue, string defaultKey) =>
        string.IsNullOrWhiteSpace(cfgValue) ? (_def.DefaultString(defaultKey) ?? string.Empty) : cfgValue;
}

using System.Text.Json;
using TranslateTheDamn.Core.Config;

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

    public ManifestHttpBackend(string id, BackendDef def, BackendConfig cfg) : base(cfg)
    {
        _id = id;
        _def = def;
    }

    public override string Id => _id;
    protected override bool HasCredential => !string.IsNullOrWhiteSpace(Cfg.ApiKey);

    private string Endpoint => string.IsNullOrWhiteSpace(Cfg.Endpoint) ? (_def.Endpoint ?? string.Empty) : Cfg.Endpoint!;
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
        ["apiKey"] = Cfg.ApiKey ?? string.Empty,
        ["model"] = Cfg.Model ?? _def.DefaultString("model") ?? string.Empty,
        ["target"] = Cfg.Target ?? _def.DefaultString("target") ?? string.Empty,
        ["format"] = Cfg.Format ?? _def.DefaultString("format") ?? string.Empty,
        ["source"] = Cfg.Source ?? string.Empty,
        ["targetLanguage"] = Cfg.TargetLanguage ?? _def.DefaultString("targetLanguage") ?? string.Empty,
        ["sourceLanguage"] = Cfg.SourceLanguage ?? string.Empty
    };
}

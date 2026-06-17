using System.Text.Json;
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.Core.Backends.Http;

/// <summary>
/// Google Cloud Translation v2 (Basic). POST with <c>x-goog-api-key</c>; body { q, target, format }
/// (omit source ⇒ auto-detect). Translated text at <c>data.translations[0].translatedText</c>.
/// </summary>
public sealed class GoogleV2Translator : HttpTranslator
{
    public GoogleV2Translator(BackendConfig cfg) : base(cfg) { }

    public override string Id => "google-v2";
    protected override bool HasCredential => !string.IsNullOrWhiteSpace(Cfg.ApiKey);

    private string Endpoint => string.IsNullOrWhiteSpace(Cfg.Endpoint)
        ? "https://translation.googleapis.com/language/translate/v2" : Cfg.Endpoint!;
    private string Target => string.IsNullOrWhiteSpace(Cfg.Target) ? "zh-CN" : Cfg.Target!;
    private string Format => string.IsNullOrWhiteSpace(Cfg.Format) ? "text" : Cfg.Format!;

    public override HttpCall BuildCall(string text)
    {
        var body = new Dictionary<string, object?>
        {
            ["q"] = text,
            ["target"] = Target,
            ["format"] = Format
        };
        if (!string.IsNullOrWhiteSpace(Cfg.Source)) body["source"] = Cfg.Source;  // omit ⇒ auto-detect

        var headers = new Dictionary<string, string> { ["x-goog-api-key"] = Cfg.ApiKey ?? string.Empty };
        return new HttpCall("POST", Endpoint, headers, JsonSerializer.Serialize(body));
    }

    public override string? ParseResponse(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty("data", out var data) &&
                data.TryGetProperty("translations", out var tr) &&
                tr.ValueKind == JsonValueKind.Array && tr.GetArrayLength() > 0 &&
                tr[0].TryGetProperty("translatedText", out var t))
                return t.GetString();
        }
        catch { /* ignore parse failure */ }
        return null;
    }
}

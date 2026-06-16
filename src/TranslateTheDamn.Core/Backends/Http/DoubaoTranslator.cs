using System.Text.Json;
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.Core.Backends.Http;

/// <summary>
/// doubao-seed-translation on Volcano Ark (火山方舟). POST to the **Responses** API (not
/// chat/completions); language goes in <c>translation_options</c> nested inside the input_text
/// content part (omit source_language ⇒ auto). Result: first <c>output[]</c> message →
/// <c>content[]</c> output_text → <c>.text</c>.
/// </summary>
public sealed class DoubaoTranslator : HttpTranslator
{
    public DoubaoTranslator(BackendConfig cfg) : base(cfg) { }

    public override string Id => "doubao";
    protected override bool HasCredential => !string.IsNullOrWhiteSpace(Cfg.ApiKey);

    private string Endpoint => string.IsNullOrWhiteSpace(Cfg.Endpoint)
        ? "https://ark.cn-beijing.volces.com/api/v3/responses" : Cfg.Endpoint!;
    private string ModelId => string.IsNullOrWhiteSpace(Cfg.Model) ? "doubao-seed-translation-250915" : Cfg.Model!;
    private string TargetLang => string.IsNullOrWhiteSpace(Cfg.TargetLanguage) ? "zh" : Cfg.TargetLanguage!;

    public override HttpCall BuildCall(string text)
    {
        var translationOptions = new Dictionary<string, object?> { ["target_language"] = TargetLang };
        if (!string.IsNullOrWhiteSpace(Cfg.SourceLanguage))
            translationOptions["source_language"] = Cfg.SourceLanguage;  // omit ⇒ auto-detect

        var body = new Dictionary<string, object?>
        {
            ["model"] = ModelId,
            ["input"] = new object[]
            {
                new Dictionary<string, object?>
                {
                    ["role"] = "user",
                    ["content"] = new object[]
                    {
                        new Dictionary<string, object?>
                        {
                            ["type"] = "input_text",
                            ["text"] = text,
                            ["translation_options"] = translationOptions
                        }
                    }
                }
            }
        };

        var headers = new Dictionary<string, string> { ["Authorization"] = $"Bearer {Cfg.ApiKey}" };
        return new HttpCall("POST", Endpoint, headers, JsonSerializer.Serialize(body));
    }

    public override string? ParseResponse(string json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (!doc.RootElement.TryGetProperty("output", out var output) || output.ValueKind != JsonValueKind.Array)
                return null;

            foreach (var item in output.EnumerateArray())
            {
                if (item.TryGetProperty("type", out var ty) && ty.GetString() == "message" &&
                    item.TryGetProperty("content", out var content) && content.ValueKind == JsonValueKind.Array)
                {
                    foreach (var part in content.EnumerateArray())
                        if (part.TryGetProperty("type", out var pt) && pt.GetString() == "output_text" &&
                            part.TryGetProperty("text", out var txt))
                            return txt.GetString();
                }
            }
        }
        catch { /* ignore parse failure */ }
        return null;
    }
}

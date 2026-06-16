using System.Net;
using System.Text;
using TranslateTheDamn.Core.Config;

namespace TranslateTheDamn.Core.Backends;

/// <summary>A built HTTP request (pure, testable): method, url, headers and JSON body.</summary>
public sealed record HttpCall(string Method, string Url, IReadOnlyDictionary<string, string> Headers, string BodyJson);

/// <summary>
/// Base for HTTP-API backends (google-v2, doubao). Concrete classes supply <see cref="BuildCall"/>
/// and <see cref="ParseResponse"/> (both pure/testable); this base owns the network round-trip,
/// credential gating and status classification.
/// </summary>
public abstract class HttpTranslator : ITranslator
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(60) };

    protected BackendConfig Cfg { get; }

    protected HttpTranslator(BackendConfig cfg) => Cfg = cfg;

    public abstract string Id { get; }
    public BackendKind Kind => BackendKind.Http;

    /// <summary>True when the user-supplied credential is present.</summary>
    protected abstract bool HasCredential { get; }

    public abstract HttpCall BuildCall(string text);
    public abstract string? ParseResponse(string json);

    public virtual async Task<TranslationResult> TranslateAsync(TranslationRequest request, CancellationToken ct)
    {
        if (!HasCredential)
            return TranslationResult.Failure(TranslateStatus.AuthFail, "请在设置中填写该后端的 API Key。");

        HttpCall call;
        try { call = BuildCall(request.Text); }
        catch (Exception ex) { return TranslationResult.Failure(TranslateStatus.UnknownFail, ex.Message); }

        using var msg = new HttpRequestMessage(new HttpMethod(call.Method), call.Url);
        foreach (var h in call.Headers)
            if (!string.Equals(h.Key, "Content-Type", StringComparison.OrdinalIgnoreCase))
                msg.Headers.TryAddWithoutValidation(h.Key, h.Value);
        msg.Content = new StringContent(call.BodyJson, new UTF8Encoding(false), "application/json");

        try
        {
            using var resp = await Http.SendAsync(msg, ct);
            var body = await resp.Content.ReadAsStringAsync(ct);
            if (!resp.IsSuccessStatusCode)
            {
                var status = resp.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden
                    ? TranslateStatus.AuthFail
                    : TranslateStatus.UnknownFail;
                return TranslationResult.Failure(status, $"HTTP {(int)resp.StatusCode}: {Truncate(body, 300)}");
            }

            var text = ParseResponse(body);
            return string.IsNullOrWhiteSpace(text)
                ? TranslationResult.Failure(TranslateStatus.BadOutput, "响应中未找到译文。")
                : TranslationResult.Successful(text!.Trim());
        }
        catch (TaskCanceledException)
        {
            return TranslationResult.Failure(TranslateStatus.Timeout, "请求超时或被取消。");
        }
        catch (Exception ex)
        {
            return TranslationResult.Failure(TranslateStatus.UnknownFail, ex.Message);
        }
    }

    public Task<AuthState> CheckAuthAsync(CancellationToken ct) =>
        Task.FromResult(HasCredential ? AuthState.Ready("已配置 API Key") : AuthState.Missing("未配置 API Key"));

    protected static string Truncate(string s, int max) =>
        string.IsNullOrEmpty(s) ? string.Empty : (s.Length <= max ? s : s[..max] + "…");
}

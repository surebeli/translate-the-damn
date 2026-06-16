using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends.Cli;

/// <summary>
/// Google Antigravity CLI: <c>agy -p {prompt} --log-file {tmp}</c>. agy isn't always on PATH
/// (falls back to <c>%LOCALAPPDATA%\agy\bin\agy.exe</c>), and on Windows <c>agy -p</c> can emit no
/// stdout (gemini-cli #27466) — so on NotFound/BadOutput we retry the configured fallback
/// (<c>gemini -p {prompt} --output-format text</c>). The log file aids silent-auth-fail diagnosis.
/// </summary>
public sealed class AgyTranslator : ProcessTranslator
{
    public AgyTranslator(BackendConfig cfg, string promptTemplate, ProcessRunner? runner = null)
        : base(cfg, promptTemplate, runner) { }

    public override string Id => "agy";
    protected override string DefaultModel => "gemini-3.5-flash";

    protected override IReadOnlyList<string> KnownInstallPaths => new[]
    {
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "agy", "bin", "agy.exe")
    };

    public override CliInvocation BuildInvocation(string prompt, string? logFilePath)
    {
        var args = logFilePath is null
            ? new[] { "-p", prompt }
            : new[] { "-p", prompt, "--log-file", logFilePath };
        return new CliInvocation(args, StdinMode.Empty, null, WantsLogFile: true);
    }

    public override async Task<TranslationResult> TranslateAsync(TranslationRequest request, CancellationToken ct)
    {
        var prompt = PromptBuilder.Build(PromptTemplate, request.Text);
        var primary = await RunCommandAsync(Cfg.Command ?? "agy", prompt, ct);
        if (primary.Ok) return primary;

        var fb = Cfg.FallbackCommand;
        if (!string.IsNullOrWhiteSpace(fb) &&
            (primary.Status is TranslateStatus.NotFound or TranslateStatus.BadOutput))
        {
            var gemini = await RunGeminiAsync(fb!, prompt, ct);
            if (gemini.Ok) return gemini;
            return primary.Status == TranslateStatus.NotFound ? gemini : primary;
        }
        return primary;
    }

    private async Task<TranslationResult> RunGeminiAsync(string command, string prompt, CancellationToken ct)
    {
        var resolved = PathResolver.Resolve(command);
        if (resolved is null)
            return TranslationResult.Failure(TranslateStatus.NotFound, $"找不到回退命令 “{command}”。");

        var args = new[] { "-p", prompt, "--output-format", "text" };
        var ceiling = Math.Max(3000, Cfg.TimeoutSec * 1000);
        var r = await Runner.RunAsync(resolved, args, StdinMode.Empty, null, ceiling, 0, null, Sandbox.Directory, ct);
        return Classify(r, null);
    }
}

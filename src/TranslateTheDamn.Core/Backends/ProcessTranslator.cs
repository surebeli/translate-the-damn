using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends;

/// <summary>
/// Base for CLI backends (claude/codex/copilot/agy). Concrete classes only supply the argv via
/// <see cref="BuildInvocation"/> and, optionally, custom output cleaning. Resolution, spawning,
/// timeout, ANSI-stripping, log-file diagnosis and status classification live here.
/// </summary>
public abstract class ProcessTranslator : ITranslator
{
    protected BackendConfig Cfg { get; }
    protected string PromptTemplate { get; }
    protected ProcessRunner Runner { get; }

    protected ProcessTranslator(BackendConfig cfg, string promptTemplate, ProcessRunner? runner = null)
    {
        Cfg = cfg;
        PromptTemplate = promptTemplate;
        Runner = runner ?? new ProcessRunner();
    }

    public abstract string Id { get; }
    public BackendKind Kind => BackendKind.Cli;

    protected abstract string DefaultModel { get; }
    protected string Model => string.IsNullOrWhiteSpace(Cfg.Model) ? DefaultModel : Cfg.Model!;
    protected virtual IReadOnlyList<string> KnownInstallPaths => Array.Empty<string>();

    /// <summary>Pure, unit-testable argv builder. <paramref name="logFilePath"/> is non-null only when <c>WantsLogFile</c>.</summary>
    public abstract CliInvocation BuildInvocation(string prompt, string? logFilePath);

    protected virtual string CleanOutput(ProcessResult r) => AnsiStripper.Strip(r.Stdout).Trim();

    public virtual Task<TranslationResult> TranslateAsync(TranslationRequest request, CancellationToken ct)
    {
        var prompt = PromptBuilder.Build(PromptTemplate, request.Text);
        return RunCommandAsync(Cfg.Command ?? Id, prompt, ct);
    }

    protected async Task<TranslationResult> RunCommandAsync(string command, string prompt, CancellationToken ct)
    {
        var resolved = PathResolver.Resolve(command, KnownInstallPaths);
        if (resolved is null)
            return TranslationResult.Failure(TranslateStatus.NotFound, $"找不到命令 “{command}”,请确认已安装并在 PATH 中。");

        var probe = BuildInvocation(prompt, null);
        string? logFile = null;
        if (probe.WantsLogFile)
        {
            logFile = Path.Combine(Path.GetTempPath(), $"ttd-{Id}-{Guid.NewGuid():N}.log");
            probe = BuildInvocation(prompt, logFile);
        }

        var ceiling = Math.Max(3000, Cfg.TimeoutSec * 1000);
        var result = await Runner.RunAsync(resolved, probe.Args, probe.StdinMode, probe.StdinText, ceiling, idleMs: 0, ExtraEnv(), Sandbox.Directory, ct);

        string? logContent = null;
        if (logFile is not null)
        {
            try { if (File.Exists(logFile)) logContent = File.ReadAllText(logFile); File.Delete(logFile); }
            catch { /* best effort */ }
        }

        return Classify(result, logContent);
    }

    protected virtual IReadOnlyDictionary<string, string>? ExtraEnv() => null;

    protected TranslationResult Classify(ProcessResult r, string? logContent)
    {
        if (r.NotFound) return TranslationResult.Failure(TranslateStatus.NotFound, r.FailureDetail ?? "命令无法启动");
        if (r.TimedOut) return TranslationResult.Failure(TranslateStatus.Timeout, $"翻译超时({Cfg.TimeoutSec}s)");

        var text = CleanOutput(r);
        if (!string.IsNullOrWhiteSpace(text)) return TranslationResult.Successful(text);

        var blob = (r.Stdout + "\n" + r.Stderr + "\n" + (logContent ?? string.Empty)).ToLowerInvariant();
        if (LooksLikeAuthError(blob))
            return TranslationResult.Failure(TranslateStatus.AuthFail, "认证失败,请在设置中登录或填写密钥。");
        if (r.ExitCode != 0)
            return TranslationResult.Failure(TranslateStatus.UnknownFail, FirstLine(r.Stderr) ?? $"退出码 {r.ExitCode}");
        return TranslationResult.Failure(TranslateStatus.BadOutput,
            "没有返回译文(可能是该 CLI 在 Windows 下的已知输出问题)。");
    }

    protected static bool LooksLikeAuthError(string lowerBlob) =>
        lowerBlob.Contains("not logged in") || lowerBlob.Contains("unauthorized") ||
        lowerBlob.Contains("authentication") || lowerBlob.Contains("auth error") ||
        lowerBlob.Contains("please run") && lowerBlob.Contains("login") ||
        lowerBlob.Contains("api key") || lowerBlob.Contains(" 401");

    protected static string? FirstLine(string s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        foreach (var line in s.Split('\n'))
        {
            var t = line.Trim();
            if (t.Length > 0) return t;
        }
        return null;
    }

    public virtual Task<AuthState> CheckAuthAsync(CancellationToken ct)
    {
        var resolved = PathResolver.Resolve(Cfg.Command ?? Id, KnownInstallPaths);
        return Task.FromResult(resolved is null
            ? AuthState.Missing($"未找到 “{Cfg.Command ?? Id}”")
            : AuthState.Unknown("已安装(认证状态在首次翻译时确认)"));
    }
}

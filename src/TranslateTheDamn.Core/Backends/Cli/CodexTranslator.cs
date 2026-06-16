using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends.Cli;

/// <summary>
/// OpenAI Codex: prompt piped to <c>codex exec --skip-git-repo-check --sandbox read-only
/// --color never -m {m} -c model_reasoning_effort="low" -</c> (the trailing <c>-</c> reads stdin,
/// avoiding the non-TTY hang). Chrome goes to stderr; clean answer on stdout.
/// </summary>
public sealed class CodexTranslator : ProcessTranslator
{
    public CodexTranslator(BackendConfig cfg, string promptTemplate, ProcessRunner? runner = null)
        : base(cfg, promptTemplate, runner) { }

    public override string Id => "codex";
    protected override string DefaultModel => "gpt-5.4-mini";

    private string Reasoning => string.IsNullOrWhiteSpace(Cfg.Reasoning) ? "low" : Cfg.Reasoning!;

    public override CliInvocation BuildInvocation(string prompt, string? logFilePath) =>
        new(new[]
        {
            "exec", "--skip-git-repo-check", "--sandbox", "read-only", "--color", "never",
            "-m", Model, "-c", $"model_reasoning_effort=\"{Reasoning}\"", "-"
        }, StdinMode.Pipe, prompt);
}

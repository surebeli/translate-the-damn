using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends.Cli;

/// <summary>GitHub Copilot CLI: <c>copilot -p {prompt} -s --no-ask-user --model {m}</c>
/// (<c>-s</c> = answer only; <c>--no-ask-user</c> stops it pausing for clarification).</summary>
public sealed class CopilotTranslator : ProcessTranslator
{
    public CopilotTranslator(BackendConfig cfg, string promptTemplate, ProcessRunner? runner = null)
        : base(cfg, promptTemplate, runner) { }

    public override string Id => "copilot";
    protected override string DefaultModel => "claude-haiku-4.5";

    public override CliInvocation BuildInvocation(string prompt, string? logFilePath) =>
        new(new[] { "-p", prompt, "-s", "--no-ask-user", "--model", Model }, StdinMode.Empty, null);
}

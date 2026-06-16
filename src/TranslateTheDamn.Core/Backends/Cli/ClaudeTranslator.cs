using System.Text.Json;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends.Cli;

/// <summary>Claude Code: <c>claude -p {prompt} --model {m} --output-format text</c> with empty stdin.</summary>
public sealed class ClaudeTranslator : ProcessTranslator
{
    public ClaudeTranslator(BackendConfig cfg, string promptTemplate, ProcessRunner? runner = null)
        : base(cfg, promptTemplate, runner) { }

    public override string Id => "claude";
    protected override string DefaultModel => "haiku";

    private string OutputFormat => string.IsNullOrWhiteSpace(Cfg.OutputFormat) ? "text" : Cfg.OutputFormat!;

    // The prompt is fed via stdin (only simple flags as args). Passing a multi-line / Chinese /
    // parenthesised prompt as a cmd.exe argument gets mangled by .NET's argv escaping vs cmd.exe's
    // own quoting rules, which makes claude hang. stdin sidesteps the shell entirely.
    public override CliInvocation BuildInvocation(string prompt, string? logFilePath) =>
        new(new[] { "-p", "--model", Model, "--output-format", OutputFormat }, StdinMode.Pipe, prompt);

    protected override string CleanOutput(ProcessResult r)
    {
        var raw = AnsiStripper.Strip(r.Stdout).Trim();
        if (raw.Length > 0 && string.Equals(OutputFormat, "json", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                using var doc = JsonDocument.Parse(raw);
                if (doc.RootElement.TryGetProperty("result", out var res) && res.ValueKind == JsonValueKind.String)
                    return res.GetString()?.Trim() ?? string.Empty;
            }
            catch { /* not JSON after all; fall through */ }
        }
        return raw;
    }
}

using System.Text.Json;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends.Manifest;

/// <summary>
/// Generic CLI backend driven by a <see cref="BackendDef"/> from the manifest. Builds argv from the
/// <c>args</c> template + <c>promptVia</c>, handles the optional fallback command, known install
/// paths, log-file diagnosis and json-result parsing — all from data, no per-backend code.
/// </summary>
public sealed class ManifestCliBackend : ProcessTranslator
{
    private readonly string _id;
    private readonly BackendDef _def;

    public ManifestCliBackend(string id, BackendDef def, BackendConfig cfg, string promptTemplate, ProcessRunner? runner = null)
        : base(cfg, promptTemplate, runner)
    {
        _id = id;
        _def = def;
    }

    public override string Id => _id;
    protected override string DefaultModel => _def.DefaultString("model") ?? string.Empty;

    private string Command => string.IsNullOrWhiteSpace(Cfg.Command) ? (_def.Command ?? _id) : Cfg.Command!;
    private string Reasoning => string.IsNullOrWhiteSpace(Cfg.Reasoning) ? (_def.DefaultString("reasoning") ?? string.Empty) : Cfg.Reasoning!;
    private string OutputFormat => string.IsNullOrWhiteSpace(Cfg.OutputFormat) ? (_def.DefaultString("outputFormat") ?? "text") : Cfg.OutputFormat!;

    protected override IReadOnlyList<string> KnownInstallPaths =>
        _def.KnownInstallPaths is not null && _def.KnownInstallPaths.TryGetValue("windows", out var p) ? p : Array.Empty<string>();

    public override CliInvocation BuildInvocation(string prompt, string? logFilePath)
    {
        var vars = new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["model"] = Model,
            ["reasoning"] = Reasoning,
            ["outputFormat"] = OutputFormat,
            ["prompt"] = prompt,
            ["logFile"] = logFilePath ?? string.Empty
        };

        var template = _def.Args ?? new List<string>();
        var args = template.Select(a => ManifestEngine.Subst(a, vars)).ToArray();
        var wantsLog = template.Any(a => a.Contains("{logFile}", StringComparison.Ordinal));

        var pipe = _def.PromptVia is "stdin" or "stdin-dash";
        return new CliInvocation(args, pipe ? StdinMode.Pipe : StdinMode.Empty, pipe ? prompt : null, wantsLog);
    }

    protected override string CleanOutput(ProcessResult r)
    {
        var raw = AnsiStripper.Strip(r.Stdout).Trim();
        if (raw.Length > 0 && string.Equals(OutputFormat, "json", StringComparison.OrdinalIgnoreCase) && _def.Parse?.JsonResultPath is { } jsonPath)
        {
            try
            {
                using var doc = JsonDocument.Parse(raw);
                var v = ManifestEngine.Eval(doc.RootElement, jsonPath);
                if (!string.IsNullOrEmpty(v)) return v.Trim();
            }
            catch { /* not JSON after all */ }
        }
        return raw;
    }

    public override async Task<TranslationResult> TranslateAsync(TranslationRequest request, CancellationToken ct)
    {
        var prompt = PromptBuilder.Build(PromptTemplate, request.Text);
        var primary = await RunCommandAsync(Command, prompt, ct);
        if (primary.Ok || string.IsNullOrWhiteSpace(_def.FallbackCommand)) return primary;

        if (primary.Status is TranslateStatus.NotFound or TranslateStatus.BadOutput)
        {
            var fb = await RunFallbackAsync(prompt, ct);
            if (fb.Ok) return fb;
            return primary.Status == TranslateStatus.NotFound ? fb : primary;
        }
        return primary;
    }

    private async Task<TranslationResult> RunFallbackAsync(string prompt, CancellationToken ct)
    {
        var cmd = _def.FallbackCommand!;
        var resolved = PathResolver.Resolve(cmd);
        if (resolved is null) return TranslationResult.Failure(TranslateStatus.NotFound, $"找不到回退命令 “{cmd}”。");

        var vars = new Dictionary<string, string>(StringComparer.Ordinal) { ["model"] = Model, ["prompt"] = prompt };
        var args = (_def.FallbackArgs ?? new List<string>()).Select(a => ManifestEngine.Subst(a, vars)).ToArray();
        var ceiling = Math.Max(3000, Cfg.TimeoutSec * 1000);
        var r = await Runner.RunAsync(resolved, args, StdinMode.Empty, null, ceiling, 0, null, Sandbox.Directory, ct);
        return Classify(r, null);
    }
}

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
    private string? FallbackCommand => string.IsNullOrWhiteSpace(Cfg.FallbackCommand) ? _def.FallbackCommand : Cfg.FallbackCommand;

    protected override IReadOnlyList<string> KnownInstallPaths =>
        _def.KnownInstallPaths is not null && _def.KnownInstallPaths.TryGetValue("windows", out var p) ? p : Array.Empty<string>();

    protected override IReadOnlyList<string> AuthSuccessSignatures =>
        _def.Probe?.SuccessSignatures ?? (IReadOnlyList<string>)Array.Empty<string>();

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
        var argv = template.Select(a => ManifestEngine.Subst(a, vars)).ToList();

        // Conditional appends (e.g. claude/copilot `--effort {reasoning}`): only when the gating var
        // is non-empty, so out-of-the-box behavior is unchanged until the user picks a tier.
        foreach (var ap in _def.ArgsAppend ?? Enumerable.Empty<ArgsAppendDef>())
            if (vars.TryGetValue(ap.When, out var w) && !string.IsNullOrEmpty(w))
                foreach (var a in ap.Args) argv.Add(ManifestEngine.Subst(a, vars));

        var args = argv.ToArray();
        var wantsLog = template.Any(a => a.Contains("{logFile}", StringComparison.Ordinal));

        var pipe = _def.PromptVia is "stdin" or "stdin-dash";
        return new CliInvocation(args, pipe ? StdinMode.Pipe : StdinMode.Empty, pipe ? prompt : null, wantsLog);
    }

    protected override string CleanOutput(ProcessResult r)
    {
        var raw = AnsiStripper.Strip(r.Stdout).Trim();
        if (raw.Length == 0) return raw;

        // JSONL / stream-json (opencode, kimi): each line is a JSON object; collect every
        // type==JsonlType object's JsonlTextPath, concatenated. Falls back to raw if nothing matched.
        if (_def.Parse?.Jsonl == true)
        {
            var sb = new System.Text.StringBuilder();
            var type = _def.Parse.JsonlType ?? "text";
            var textPath = _def.Parse.JsonlTextPath ?? "text";
            foreach (var line in raw.Split('\n'))
            {
                var t = line.Trim();
                if (t.Length == 0 || (t[0] != '{' && t[0] != '[')) continue;
                try { using var doc = JsonDocument.Parse(t); CollectJsonlText(doc.RootElement, type, textPath, sb); }
                catch { /* not a JSON line (chrome) — skip */ }
            }
            var collected = sb.ToString().Trim();
            return collected.Length > 0 ? collected : raw;
        }

        if (string.Equals(OutputFormat, "json", StringComparison.OrdinalIgnoreCase) && _def.Parse?.JsonResultPath is { } jsonPath)
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

    /// <summary>Recursively collect the text of every object whose <c>type</c> == <paramref name="type"/>,
    /// read via <paramref name="textPath"/> (handles flat events like opencode and content-part arrays like kimi).</summary>
    private static void CollectJsonlText(JsonElement el, string type, string textPath, System.Text.StringBuilder sb)
    {
        switch (el.ValueKind)
        {
            case JsonValueKind.Object:
                if (el.TryGetProperty("type", out var tEl) && tEl.ValueKind == JsonValueKind.String && tEl.GetString() == type)
                {
                    var txt = ManifestEngine.Eval(el, textPath);
                    if (!string.IsNullOrEmpty(txt)) sb.Append(txt);
                }
                foreach (var p in el.EnumerateObject()) CollectJsonlText(p.Value, type, textPath, sb);
                break;
            case JsonValueKind.Array:
                foreach (var item in el.EnumerateArray()) CollectJsonlText(item, type, textPath, sb);
                break;
        }
    }

    public override async Task<TranslationResult> TranslateAsync(TranslationRequest request, CancellationToken ct)
    {
        var prompt = PromptBuilder.Build(PromptTemplate, request.Text);
        var primary = await RunCommandAsync(Command, prompt, ct);
        if (primary.Ok || string.IsNullOrWhiteSpace(FallbackCommand)) return primary;

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
        var cmd = FallbackCommand!;
        var resolved = PathResolver.Resolve(cmd);
        if (resolved is null) return TranslationResult.Failure(TranslateStatus.NotFound, $"找不到回退命令 “{cmd}”。");

        var vars = new Dictionary<string, string>(StringComparer.Ordinal) { ["model"] = Model, ["prompt"] = prompt };
        var args = (_def.FallbackArgs ?? new List<string>()).Select(a => ManifestEngine.Subst(a, vars)).ToArray();
        var ceiling = Math.Max(3000, Cfg.TimeoutSec * 1000);
        var r = await Runner.RunAsync(resolved, args, StdinMode.Empty, null, ceiling, 0, null, Sandbox.Directory, ct);
        return Classify(r, null);
    }
}

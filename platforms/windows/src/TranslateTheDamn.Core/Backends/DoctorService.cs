using TranslateTheDamn.Core.Backends.Manifest;
using TranslateTheDamn.Core.Config;
using TranslateTheDamn.Core.Util;

namespace TranslateTheDamn.Core.Backends;

/// <summary>
/// Generic, manifest-driven backend "doctor" (spec §9): a non-interactive connectivity/auth probe
/// plus reporting of the static model catalog + effort tiers. No per-vendor branching — it reads each
/// backend's <c>probe</c> verb from <c>spec/backends.json</c> (Constitution Law 6). Depth is a local
/// credential check by default; <paramref name="deep"/> adds a billable live <c>-p</c> translate
/// probe. The report never carries the API key. Runs from the neutral sandbox CWD, bounded by the
/// per-backend <c>timeoutSec</c> ceiling; agy's keyring cold-start is handled by bounded retry that
/// reports the final state (transient first-attempt failure → degraded, not fail).
/// </summary>
public sealed class DoctorService
{
    private readonly BackendManifest _manifest;
    private readonly ProcessRunner _runner;
    private readonly string _promptTemplate;

    public DoctorService(string promptTemplate = "{content}", ProcessRunner? runner = null)
    {
        _manifest = BackendManifest.Load();
        _runner = runner ?? new ProcessRunner();
        _promptTemplate = promptTemplate;
    }

    public async Task<DoctorReport> RunAsync(string backendId, BackendConfig cfg, bool deep, CancellationToken ct)
    {
        var checks = new List<DoctorCheck>();
        if (!_manifest.Backends.TryGetValue(backendId, out var def))
            return new DoctorReport(backendId, DoctorStatus.Unknown,
                new[] { new DoctorCheck("后端", DoctorStatus.Unknown, $"未知后端 “{backendId}”") });

        // 1. binary presence (PATH + known install locations)
        var command = string.IsNullOrWhiteSpace(cfg.Command) ? (def.Command ?? backendId) : cfg.Command!;
        var known = def.KnownInstallPaths is not null && def.KnownInstallPaths.TryGetValue("windows", out var kp)
            ? kp : (IReadOnlyList<string>)Array.Empty<string>();
        var resolved = PathResolver.Resolve(command, known);
        if (resolved is null)
        {
            checks.Add(new DoctorCheck("可执行文件", DoctorStatus.Fail, $"未找到 “{command}”(请确认已安装并在 PATH 中)"));
            return new DoctorReport(backendId, DoctorStatus.Fail, checks);
        }
        checks.Add(new DoctorCheck("可执行文件", DoctorStatus.Ok, resolved.ResolvedPath));

        // 2. auth (local): manifest probe argv (claude/codex), cred-file presence (agy), or none (copilot)
        // Cap the local probe at 15s (a ceiling, not a floor) so a large timeoutSec can't hang the dialog.
        var ceiling = Math.Clamp(cfg.TimeoutSec * 1000, 3000, 15000);
        var probe = def.Probe;
        if (probe?.Args is { Count: > 0 })
            checks.Add(await RunArgsProbeAsync(resolved, probe, ceiling, ct));
        else if (probe?.CredFiles is { Count: > 0 })
        {
            var present = probe.CredFiles.Any(f => File.Exists(ExpandPath(f)));
            checks.Add(new DoctorCheck("认证(本地凭据文件)", present ? DoctorStatus.Ok : DoctorStatus.Unknown,
                present ? "找到本地 OAuth 凭据文件(未做联网验证)" : "未找到本地凭据文件;勾选“深度检测”可联网验证"));
        }
        else
            checks.Add(new DoctorCheck("认证", DoctorStatus.Unknown, "该后端无非交互认证检查;勾选“深度检测”发一次联网探测"));

        // 3. deep live probe (opt-in, billable) — a tiny real translation through the normal path
        if (deep)
            checks.Add(await RunDeepProbeAsync(backendId, def, cfg, ct));

        // 4. informational rows
        checks.Add(new DoctorCheck("模型列表", DoctorStatus.Ok,
            def.ModelsCmd is { Count: > 0 } mc
                ? $"可经 “{command} {string.Join(' ', mc)}” 实时枚举"
                : "使用应用内置目录(该 CLI 无法非交互枚举模型)"));
        if (def.EffortTiers is { Count: > 0 } tiers)
            checks.Add(new DoctorCheck("Effort 档位", DoctorStatus.Ok, string.Join(" / ", tiers)));

        return new DoctorReport(backendId, Aggregate(checks), checks);
    }

    /// <summary>Expand a manifest credFile path cross-platform: a leading <c>~/</c> → the user's home
    /// (the shared, platform-neutral form — macOS expands it the same way), and any remaining
    /// <c>%VAR%</c> tokens via the environment (backward-compatible).</summary>
    private static string ExpandPath(string p)
    {
        if (p.StartsWith("~/", StringComparison.Ordinal) || p.StartsWith("~\\", StringComparison.Ordinal))
            p = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), p[2..]);
        return Environment.ExpandEnvironmentVariables(p);
    }

    /// <summary>Local auth probe with bounded retry that reports the FINAL state (agy keyring race).</summary>
    private async Task<DoctorCheck> RunArgsProbeAsync(ResolvedCommand cmd, ProbeDef probe, int ceiling, CancellationToken ct)
    {
        var attempts = Math.Max(1, probe.Retries + 1);
        var sawFail = false;
        var detail = "无法判定认证状态";
        for (var i = 0; i < attempts; i++)
        {
            if (ct.IsCancellationRequested) break;
            if (i > 0) { try { await Task.Delay(1200, ct); } catch { break; } }
            var r = await _runner.RunAsync(cmd, probe.Args!, StdinMode.Empty, null, ceiling, 0, null, Sandbox.Directory, ct);
            var status = ProbeClassifier.Classify(probe.SuccessSignatures, probe.FailSignatures, r.Stdout + "\n" + r.Stderr, probe.FailWins);
            if (status == ProbeStatus.Ok || (probe.ExitZeroIsAuth && r.ExitCode == 0))
                return new DoctorCheck("认证(本地凭据)", sawFail ? DoctorStatus.Degraded : DoctorStatus.Ok,
                    sawFail ? "已登录(首次尝试瞬时失败,重试通过 — 可能是 keyring 冷启动)"
                            : probe.Network ? "已登录(联网验证)" : "已登录(本地凭据;未做联网验证)");
            // Status-only — never surface raw stdout/stderr (may contain paths/env/diagnostics).
            if (status == ProbeStatus.Fail) { sawFail = true; detail = "未登录(本地凭据检查未通过;勾选“深度检测”可联网验证)"; }
        }
        return new DoctorCheck("认证", sawFail ? DoctorStatus.Fail : DoctorStatus.Unknown, detail);
    }

    /// <summary>Opt-in billable end-to-end probe: a tiny real translation, classified by status. Uses
    /// the manifest <c>probe.retries</c> (bounded retry — recovers the agy keyring cold-start race,
    /// reporting degraded vs fail), capped at 30s total, and never surfaces a raw exception message
    /// (CLI backends only, but sanitized so nothing process/env-derived leaks).</summary>
    private async Task<DoctorCheck> RunDeepProbeAsync(string id, BackendDef def, BackendConfig cfg, CancellationToken ct)
    {
        var attempts = Math.Max(1, (def.Probe?.Retries ?? 0) + 1);
        var sawFail = false;
        var detail = "未返回译文";
        using var deepCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        deepCts.CancelAfter(Math.Clamp(cfg.TimeoutSec * 1000, 3000, 30000));
        for (var i = 0; i < attempts; i++)
        {
            if (deepCts.IsCancellationRequested) break;
            if (i > 0) { try { await Task.Delay(1200, deepCts.Token); } catch { break; } }
            try
            {
                var t = new ManifestCliBackend(id, def, cfg, _promptTemplate, _runner);
                var res = await t.TranslateAsync(new TranslationRequest("ping"), deepCts.Token);
                switch (res.Status)
                {
                    case TranslateStatus.Success:
                        return new DoctorCheck("联网验证(深度)", sawFail ? DoctorStatus.Degraded : DoctorStatus.Ok,
                            sawFail ? "实测成功(首次失败,重试通过 — 可能是 keyring 冷启动)" : "实测翻译成功");
                    // Status-only details — never surface res.Error (it can derive from raw stderr).
                    case TranslateStatus.NotFound:
                        return new DoctorCheck("联网验证(深度)", DoctorStatus.Fail, "命令未找到(未在 PATH/已知路径)");
                    case TranslateStatus.AuthFail:
                        return new DoctorCheck("联网验证(深度)", DoctorStatus.Fail, "认证失败");   // terminal: don't burn billable retries on a real auth failure
                    case TranslateStatus.Timeout:  sawFail = true; detail = "超时"; break;
                    default:                       sawFail = true; detail = "未返回有效译文"; break;
                }
            }
            catch (OperationCanceledException) { detail = "已取消"; break; }
            catch (Exception ex) { sawFail = true; detail = "深度探测出错(" + ex.GetType().Name + ")"; }
        }
        return new DoctorCheck("联网验证(深度)", sawFail ? DoctorStatus.Fail : DoctorStatus.Unknown, detail);
    }

    private static DoctorStatus Aggregate(IReadOnlyList<DoctorCheck> checks)
    {
        if (checks.Any(c => c.Status == DoctorStatus.Fail)) return DoctorStatus.Fail;
        if (checks.Any(c => c.Status == DoctorStatus.Degraded)) return DoctorStatus.Degraded;
        if (checks.Any(c => c.Status == DoctorStatus.Unknown)) return DoctorStatus.Unknown;
        return DoctorStatus.Ok;
    }
}

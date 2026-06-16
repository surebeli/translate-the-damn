using System.Diagnostics;
using System.Text;

namespace TranslateTheDamn.Core.Util;

public enum StdinMode { None, Empty, Pipe }

public sealed record ProcessResult(
    int ExitCode,
    string Stdout,
    string Stderr,
    bool TimedOut,
    bool NotFound,
    long DurationMs,
    string? FailureDetail = null);

/// <summary>
/// Spawns a child process and captures clean stdout/stderr with a ceiling timeout (and optional
/// idle timeout), killing the whole process tree on timeout/cancel. Used by CLI translators.
/// </summary>
public sealed class ProcessRunner
{
    public async Task<ProcessResult> RunAsync(
        ResolvedCommand cmd,
        IReadOnlyList<string> args,
        StdinMode stdinMode,
        string? stdinText,
        int ceilingMs,
        int idleMs,
        IReadOnlyDictionary<string, string>? extraEnv,
        CancellationToken ct)
    {
        var psi = new ProcessStartInfo
        {
            FileName = cmd.Executable,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = stdinMode != StdinMode.None,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var a in cmd.PrependArgs) psi.ArgumentList.Add(a);
        foreach (var a in args) psi.ArgumentList.Add(a);
        if (extraEnv is not null)
            foreach (var kv in extraEnv) psi.Environment[kv.Key] = kv.Value;

        var sw = Stopwatch.StartNew();
        using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };

        var sbOut = new StringBuilder();
        var sbErr = new StringBuilder();
        long lastActivity = 0;
        void Mark() => Interlocked.Exchange(ref lastActivity, sw.ElapsedMilliseconds);

        proc.OutputDataReceived += (_, e) => { if (e.Data is not null) { lock (sbOut) sbOut.AppendLine(e.Data); Mark(); } };
        proc.ErrorDataReceived += (_, e) => { if (e.Data is not null) { lock (sbErr) sbErr.AppendLine(e.Data); Mark(); } };

        try { proc.Start(); }
        catch (Exception ex)
        {
            return new ProcessResult(-1, string.Empty, string.Empty, false, NotFound: true, sw.ElapsedMilliseconds, ex.Message);
        }

        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        if (stdinMode == StdinMode.Empty)
        {
            try { proc.StandardInput.Close(); } catch { /* ignore */ }
        }
        else if (stdinMode == StdinMode.Pipe)
        {
            try
            {
                await proc.StandardInput.WriteAsync((stdinText ?? string.Empty).AsMemory(), ct);
                proc.StandardInput.Close();
            }
            catch { /* ignore broken pipe */ }
        }

        bool timedOut = false, canceled = false;
        while (!proc.HasExited)
        {
            try { await Task.Delay(75, ct); }
            catch (OperationCanceledException) { canceled = true; break; }

            var elapsed = sw.ElapsedMilliseconds;
            if (ceilingMs > 0 && elapsed > ceilingMs) { timedOut = true; break; }
            if (idleMs > 0 && elapsed > idleMs && elapsed - Interlocked.Read(ref lastActivity) > idleMs) { timedOut = true; break; }
        }

        if (!proc.HasExited) KillTree(proc);
        try { proc.WaitForExit(2000); } catch { /* ignore */ }
        sw.Stop();

        var exit = SafeExitCode(proc);
        string outStr, errStr;
        lock (sbOut) outStr = sbOut.ToString();
        lock (sbErr) errStr = sbErr.ToString();

        if (canceled) return new ProcessResult(exit, outStr, errStr, false, false, sw.ElapsedMilliseconds, "canceled");
        return new ProcessResult(exit, outStr, errStr, timedOut, false, sw.ElapsedMilliseconds, timedOut ? "timeout" : null);
    }

    private static int SafeExitCode(Process p)
    {
        try { return p.HasExited ? p.ExitCode : -1; } catch { return -1; }
    }

    private static void KillTree(Process proc)
    {
        try
        {
            if (OperatingSystem.IsWindows())
            {
                using var k = Process.Start(new ProcessStartInfo("taskkill", $"/PID {proc.Id} /T /F")
                { CreateNoWindow = true, UseShellExecute = false });
                k?.WaitForExit(3000);
            }
        }
        catch { /* fall through to managed kill */ }
        try { if (!proc.HasExited) proc.Kill(true); } catch { /* ignore */ }
    }
}

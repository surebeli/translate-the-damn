namespace TranslateTheDamn.Core.Util;

/// <summary>A command resolved to something spawnable: the executable plus any wrapper args.</summary>
public sealed record ResolvedCommand(string Executable, IReadOnlyList<string> PrependArgs, string ResolvedPath);

/// <summary>
/// Resolves a CLI command to a spawnable form without launching a subprocess (ported from
/// hopper-plugin's path-resolve.js). Walks PATH with a deterministic extension preference, wraps
/// <c>.cmd/.bat</c> via <c>cmd.exe /c</c> and <c>.ps1</c> via PowerShell, and falls back to
/// caller-supplied known install paths (e.g. agy at <c>%LOCALAPPDATA%\agy\bin\agy.exe</c>).
/// </summary>
public static class PathResolver
{
    private static readonly bool IsWindows = OperatingSystem.IsWindows();

    // Prefer easily-spawnable forms: a .cmd shim before a .ps1 shim (npm ships both).
    private static readonly string[] WindowsExtPreference = { ".exe", ".com", ".cmd", ".bat", ".ps1" };

    public static ResolvedCommand? Resolve(string command, IEnumerable<string>? knownInstallPaths = null)
    {
        if (string.IsNullOrWhiteSpace(command)) return null;

        if (IsQualified(command))
        {
            if (File.Exists(command)) return Wrap(command);
            if (IsWindows && !Path.HasExtension(command))
                foreach (var ext in WindowsExtPreference)
                    if (File.Exists(command + ext)) return Wrap(command + ext);
            return null;
        }

        var onPath = ResolveOnPath(command);
        if (onPath is not null) return onPath;

        if (knownInstallPaths is not null)
            foreach (var p in knownInstallPaths)
            {
                var expanded = Environment.ExpandEnvironmentVariables(p);
                if (File.Exists(expanded)) return Wrap(expanded);
            }

        return null;
    }

    private static ResolvedCommand? ResolveOnPath(string command)
    {
        var pathDirs = (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        if (!IsWindows)
        {
            foreach (var dir in pathDirs)
            {
                var full = Path.Combine(dir, command);
                if (File.Exists(full)) return new ResolvedCommand(full, Array.Empty<string>(), full);
            }
            return null;
        }

        if (Path.HasExtension(command))
        {
            foreach (var dir in pathDirs)
            {
                var full = Path.Combine(dir, command);
                if (File.Exists(full)) return Wrap(full);
            }
            return null;
        }

        foreach (var ext in WindowsExtPreference)
            foreach (var dir in pathDirs)
            {
                var full = Path.Combine(dir, command + ext);
                if (File.Exists(full)) return Wrap(full);
            }
        return null;
    }

    private static ResolvedCommand Wrap(string fullPath)
    {
        var ext = Path.GetExtension(fullPath).ToLowerInvariant();
        return ext switch
        {
            ".cmd" or ".bat" => new ResolvedCommand("cmd.exe", new[] { "/c", fullPath }, fullPath),
            ".ps1" => new ResolvedCommand("powershell.exe",
                new[] { "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", fullPath }, fullPath),
            _ => new ResolvedCommand(fullPath, Array.Empty<string>(), fullPath)
        };
    }

    private static bool IsQualified(string command) =>
        command.Contains('/') || command.Contains('\\') ||
        (IsWindows && command.Length >= 2 && command[1] == ':');
}

namespace TranslateTheDamn.Core.Util;

/// <summary>
/// A neutral, empty working directory used as the CWD for all CLI backends. Spawning agent CLIs
/// from here prevents them from loading whatever project the user happens to be in (CLAUDE.md /
/// AGENTS.md / .claude hooks / project .mcp.json), which would be slow and irrelevant to translation.
/// </summary>
public static class Sandbox
{
    private static string? _dir;

    public static string Directory
    {
        get
        {
            if (_dir is not null) return _dir;
            var d = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "translatethedamn", "sandbox");
            try { System.IO.Directory.CreateDirectory(d); }
            catch { d = Path.GetTempPath(); }
            _dir = d;
            return d;
        }
    }
}

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace TranslateTheDamn.Core;

/// <summary>
/// Locale-aware shared UI strings loader — the Windows mirror of the macOS <c>StringsLoader</c>.
///
/// Catalog = <c>strings/en.json</c> (BASE) overlaid by <c>strings/&lt;localeId&gt;.json</c> (the resolved
/// locale overrides en). A key missing from the resolved locale therefore falls back to en, then to the
/// key string itself. The resolved locale is set ONCE at startup via <see cref="Configure"/> (the App
/// resolves it from <c>config.General.UiLanguage</c> + the system locale via <see cref="LocaleResolver"/>)
/// and can be hot-switched at runtime (Settings "Display language") via Configure + <see cref="Reload"/>.
///
/// The app's DISPLAY language is SEPARATE from the translation TARGET language
/// (<see cref="Config.TranslationConfig.TargetLanguage"/>) — never conflate the two.
///
/// Lives in Core (no WPF dependency) so it is pure + the conformance test project compile-checks it.
/// </summary>
public static class StringsLoader
{
    private static readonly object Gate = new();
    private static Dictionary<string, string>? _cache;
    private static string _localeId = "en";

    /// <summary>Set the resolved UI locale and drop the cache so the next access reloads it. Call once at
    /// startup (before building any window/tray/popup) and again on a Settings "Display language" switch.</summary>
    public static void Configure(string localeId)
    {
        lock (Gate)
        {
            _localeId = string.IsNullOrWhiteSpace(localeId) ? "en" : localeId;
            _cache = null;
        }
    }

    /// <summary>Drop the cache so the next access reloads it (hot-switch after <see cref="Configure"/>).</summary>
    public static void Reload()
    {
        lock (Gate) { _cache = null; }
    }

    /// <summary>The localized string for <paramref name="key"/>, or the key itself if absent everywhere.</summary>
    public static string Get(string key)
    {
        Dictionary<string, string> c;
        lock (Gate) { c = _cache ??= Build(); }
        return c.TryGetValue(key, out var v) ? v : key;
    }

    private static Dictionary<string, string> Build()
    {
        // BASE = en (full key set); OVERLAY = resolved locale (overrides en).
        var merged = LoadLocaleFile("en") ?? new Dictionary<string, string>(StringComparer.Ordinal);
        if (!string.Equals(_localeId, "en", StringComparison.Ordinal))
        {
            var overlay = LoadLocaleFile(_localeId);
            if (overlay is not null)
                foreach (var kv in overlay) merged[kv.Key] = kv.Value;   // resolved locale overrides en
        }
        return merged;
    }

    /// <summary>Load <c>strings/&lt;locale&gt;.json</c>'s <c>"strings"</c> map. Searches the app dir then
    /// walks up to the repo root (mirrors the macOS multi-path search + <c>Conformance.FindUp</c>): the
    /// built app has the files copied beside the exe (csproj Content), a dev run finds the repo-root copy.</summary>
    private static Dictionary<string, string>? LoadLocaleFile(string locale)
    {
        var file = locale + ".json";
        var d = new DirectoryInfo(AppContext.BaseDirectory);
        while (d is not null)
        {
            var candidate = Path.Combine(d.FullName, "strings", file);
            if (File.Exists(candidate))
            {
                try
                {
                    using var doc = JsonDocument.Parse(File.ReadAllText(candidate));
                    if (doc.RootElement.TryGetProperty("strings", out var s) && s.ValueKind == JsonValueKind.Object)
                    {
                        var map = new Dictionary<string, string>(StringComparer.Ordinal);
                        foreach (var p in s.EnumerateObject())
                            if (p.Value.ValueKind == JsonValueKind.String)
                                map[p.Name] = p.Value.GetString() ?? string.Empty;
                        return map;
                    }
                }
                catch
                {
                    // Malformed file — keep walking up; never throw out of the UI string path.
                }
            }
            d = d.Parent;
        }
        return null;
    }
}

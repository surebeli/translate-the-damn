using System;
using System.Globalization;

namespace TranslateTheDamn.Core;

/// <summary>
/// Pure UI-locale resolution (spec §3 → <c>conformance/i18n-locale-resolve.json</c>) — the Windows
/// mirror of the macOS <c>LocaleResolver</c>. Decides which UI DISPLAY language the app shows. This is
/// SEPARATE from the translation TARGET language (<see cref="Config.TranslationConfig.TargetLanguage"/>):
/// a user may run an English UI while translating into Japanese. The two are independent — never conflate.
///
/// Order (identical to macOS, pinned by the shared conformance vector so resolution never drifts — Law 2):
///   1. Explicit override — a non-empty <paramref name="configUiLang"/> that is in <see cref="Available"/> wins.
///   2. Follow system — map <paramref name="systemLocale"/> by primary language subtag (case-insensitive):
///      zh* → zh-CN (v1: all Chinese), ja* → ja, ko* → ko, en* → en.
///   3. Fallback — anything else (unsupported / empty) → en.
/// </summary>
public static class LocaleResolver
{
    public static readonly string[] Available = { "zh-CN", "en", "ja", "ko" };

    /// <summary>
    /// The user's ACTUAL system UI language — use this for the <paramref name="systemLocale"/> argument.
    /// <c>CultureInfo.CurrentUICulture</c> reflects the user's chosen Windows display language (e.g. "en-US").
    /// (Analogous to macOS's <c>Locale.preferredLanguages.first</c>, not a dev-region fallback.)
    /// </summary>
    public static string SystemLocaleId()
        => CultureInfo.CurrentUICulture?.Name ?? string.Empty;

    public static string Resolve(string configUiLang, string systemLocale)
    {
        var cfg = (configUiLang ?? string.Empty).Trim();
        if (cfg.Length > 0 && Array.IndexOf(Available, cfg) >= 0) return cfg;   // explicit override

        var s = (systemLocale ?? string.Empty).ToLowerInvariant();
        var lang = s.Split('-', '_')[0];                                       // primary subtag ("" if empty)
        return lang switch
        {
            "zh" => "zh-CN",
            "ja" => "ja",
            "ko" => "ko",
            "en" => "en",
            _ => "en",
        };
    }
}

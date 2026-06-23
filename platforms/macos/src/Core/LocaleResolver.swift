import Foundation

/// Pure UI-locale resolution (spec §3 → `conformance/i18n-locale-resolve.json`).
///
/// This decides which UI language the app shows — SEPARATE from the translation TARGET language
/// (`translation.targetLanguage`). A user may run an English UI while translating into Japanese, etc.
/// The two are independent and must never be conflated.
///
/// Resolution order:
///   1. Explicit override — non-empty `configUiLang` that is in `available` wins.
///   2. Follow system — map `systemLocale` to `available` by primary language subtag (case-insensitive):
///      `zh*` → `zh-CN` (v1: all Chinese → zh-CN until a zh-TW locale exists), `ja*` → `ja`,
///      `ko*` → `ko`, `en*` → `en`.
///   3. Fallback — anything else (unsupported / empty) → `en` (global default).
///
/// Both platforms read the same shared `conformance/i18n-locale-resolve.json` so resolution never drifts.
public enum LocaleResolver {
    public static let available = ["zh-CN", "en", "ja", "ko"]

    /// The user's ACTUAL system UI language — pass this as the `systemLocale` argument.
    ///
    /// NOT `Locale.current.identifier`: for an app that ships no `.lproj` bundles, `Locale.current`
    /// is resolved against the (empty) bundle localizations and falls back to the development region
    /// (zh-CN here), so "follow system" would wrongly report Chinese even on an English Mac.
    /// `Locale.preferredLanguages.first` is the user's real preferred language from System Settings.
    public static func systemLocaleId() -> String {
        Locale.preferredLanguages.first ?? Locale.current.identifier
    }

    public static func resolve(configUiLang: String, systemLocale: String) -> String {
        let cfg = configUiLang.trimmingCharacters(in: .whitespaces)
        if !cfg.isEmpty, available.contains(cfg) { return cfg }   // explicit override
        let lang = systemLocale.lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init) ?? ""
        switch lang {
        case "zh": return "zh-CN"
        case "ja": return "ja"
        case "ko": return "ko"
        case "en": return "en"
        default: return "en"
        }
    }
}

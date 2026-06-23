using System.Text.Json;
using System.Text.Json.Serialization;

namespace TranslateTheDamn.Core.Config;

/// <summary>
/// Strongly-typed view of <c>%USERPROFILE%\.translatethedamn\config.json</c> — the single
/// source of truth. Property initializers double as tolerance for missing keys on load.
/// </summary>
public sealed class AppConfig
{
    public int Version { get; set; } = 1;
    public GeneralConfig General { get; set; } = new();
    public HotkeyConfig Hotkey { get; set; } = new();
    public PopupConfig Popup { get; set; } = new();
    public TranslationConfig Translation { get; set; } = new();
    public Dictionary<string, BackendConfig> Backends { get; set; } = new();
    public Dictionary<string, List<string>> ModelCatalog { get; set; } = new();
}

public sealed class GeneralConfig
{
    public bool ListenClipboard { get; set; } = true;
    public string ActiveBackend { get; set; } = "claude";
    public bool StartWithWindows { get; set; } = false;

    /// <summary>UI DISPLAY language (spec §4): "" = follow the system language, else a locale id from
    /// <see cref="LocaleResolver.Available"/> (zh-CN/en/ja/ko). SEPARATE from the translation TARGET
    /// language (<see cref="TranslationConfig.TargetLanguage"/>) — never conflate. Additive/optional,
    /// no config-version bump. Mirrors macOS <c>general.uiLanguage</c>.</summary>
    public string UiLanguage { get; set; } = "";
}

public sealed class HotkeyConfig
{
    /// <summary>
    /// Windows per-platform default translate hotkey (spec §7). Deliberately NOT a shared contract:
    /// the default hotkey is each platform's own choice (macOS picks its own), so it is un-pinned from
    /// the shared <c>config-defaults</c> vector. Single source for both the deserialization fallback
    /// below and <see cref="DefaultConfig"/>.
    /// </summary>
    public const string DefaultTranslate = "Shift+Alt+C";

    public string Translate { get; set; } = DefaultTranslate;
    public string ToggleListen { get; set; } = "";
}

public sealed class PopupConfig
{
    public string Style { get; set; } = "acrylic";      // acrylic | solid
    public int AutoDismissSeconds { get; set; } = 6;
    public bool KeepOnHover { get; set; } = true;
    public string Position { get; set; } = "top-center";
}

public sealed class TranslationConfig
{
    /// <summary>Unified target language (display name, e.g. "简体中文"/"English") injected into the prompt
    /// via the <c>{target}</c> placeholder for ALL prompt-driven backends (CLI + openai-http/anthropic-http).
    /// google-v2/doubao use their own <c>Target</c>/<c>TargetLanguage</c> code fields instead.</summary>
    public string TargetLanguage { get; set; } = "简体中文";
    public string TargetLanguageDefault { get; set; } = "zh-CN";   // legacy; unused by the prompt path
    public int MaxChars { get; set; } = 8000;
    public string PromptTemplate { get; set; } = "";
}

/// <summary>
/// Per-backend settings. Heterogeneous across cli vs http backends, so all fields are optional;
/// unknown keys round-trip via <see cref="Extra"/> for forward compatibility.
/// </summary>
public sealed class BackendConfig
{
    public string Type { get; set; } = "cli";           // cli | http

    // --- cli ---
    public string? Command { get; set; }
    public string? Model { get; set; }
    public string? Reasoning { get; set; }
    public string? OutputFormat { get; set; }
    public string? FallbackCommand { get; set; }
    public int TimeoutSec { get; set; } = 30;

    // --- http ---
    public string? Endpoint { get; set; }
    public string? ApiKey { get; set; }
    // For a custom provider whose id is NOT a manifest entry: selects the generic HTTP template
    // ("openai" -> openai-http /chat/completions, "anthropic" -> anthropic-http /messages). Null/empty
    // for built-in backends (resolved by id). Additive/optional — no config-version bump (Law 4).
    // NOTE: mirror this typed field to macOS BackendConfig.swift + BackendTestConfig in lockstep.
    public string? Protocol { get; set; }
    public string? Target { get; set; }            // google-v2
    public string? Source { get; set; }            // google-v2
    public string? Format { get; set; }            // google-v2
    public string? TargetLanguage { get; set; }    // doubao
    public string? SourceLanguage { get; set; }    // doubao

    [JsonExtensionData]
    public Dictionary<string, JsonElement>? Extra { get; set; }

    [JsonIgnore]
    public BackendKind Kind => string.Equals(Type, "http", StringComparison.OrdinalIgnoreCase)
        ? BackendKind.Http
        : BackendKind.Cli;
}

namespace TranslateTheDamn.Core.Config;

/// <summary>
/// The hardcoded first-run bootstrap. When config.json is absent, this exact shape is written
/// to disk and thereafter the settings UI only reads/writes the file. Intentionally temporary:
/// <see cref="AppConfig.ModelCatalog"/> may later be replaced by a remote/dynamic catalog.
/// </summary>
public static class DefaultConfig
{
    public const string DefaultPromptTemplate =
        "源语言为英文时,专业术语/技术名词保留英文,其余描述性内容译为简体中文。\n" +
        "源语言为非英文时,全部译为简体中文(含代码注释、变量名解释)。\n" +
        "代码块、命令行、配置示例保持原样,仅翻译其中说明性文字。只输出译文,不要任何前后缀。\n\n" +
        "内容:\n{content}";

    public static AppConfig Create() => new()
    {
        Version = 1,
        General = new GeneralConfig { ListenClipboard = true, ActiveBackend = "claude", StartWithWindows = false },
        Hotkey = new HotkeyConfig { Translate = HotkeyConfig.DefaultTranslate, ToggleListen = "" },
        Popup = new PopupConfig { Style = "acrylic", AutoDismissSeconds = 6, KeepOnHover = true, Position = "top-center" },
        Translation = new TranslationConfig
        {
            TargetLanguageDefault = "zh-CN",
            MaxChars = 8000,
            PromptTemplate = DefaultPromptTemplate
        },
        Backends = new Dictionary<string, BackendConfig>
        {
            ["claude"]  = new() { Type = "cli", Command = "claude", Model = "haiku", OutputFormat = "text", TimeoutSec = 60 },
            ["codex"]   = new() { Type = "cli", Command = "codex", Model = "gpt-5.4-mini", Reasoning = "low", TimeoutSec = 60 },
            ["copilot"] = new() { Type = "cli", Command = "copilot", Model = "claude-haiku-4.5", TimeoutSec = 60 },
            ["agy"]     = new() { Type = "cli", Command = "agy", Model = "gemini-3.5-flash", FallbackCommand = "gemini", TimeoutSec = 60 },
            ["google-v2"] = new() { Type = "http", Endpoint = "https://translation.googleapis.com/language/translate/v2", ApiKey = "", Target = "zh-CN", Source = "", Format = "text" },
            ["doubao"]  = new() { Type = "http", Endpoint = "https://ark.cn-beijing.volces.com/api/v3/responses", ApiKey = "", Model = "doubao-seed-translation-250915", TargetLanguage = "zh", SourceLanguage = "" }
        },
        ModelCatalog = new Dictionary<string, List<string>>
        {
            ["claude"]  = new() { "haiku", "sonnet", "opus", "fable" },
            ["codex"]   = new() { "gpt-5.4-mini", "gpt-5.4", "gpt-5.5" },
            ["copilot"] = new() { "claude-haiku-4.5", "claude-sonnet-4.6", "gpt-5.4", "gemini-3.5-flash" },
            ["agy"]     = new() { "gemini-3.5-flash", "gemini-3.1-pro" },
            ["google-v2"] = new() { "nmt" },
            ["doubao"]  = new() { "doubao-seed-translation-250915" }
        }
    };
}

namespace TranslateTheDamn.Core.Config;

/// <summary>
/// The hardcoded first-run bootstrap. When config.json is absent, this exact shape is written
/// to disk and thereafter the settings UI only reads/writes the file. Intentionally temporary:
/// <see cref="AppConfig.ModelCatalog"/> may later be replaced by a remote/dynamic catalog.
/// </summary>
public static class DefaultConfig
{
    // {target} is resolved ONCE (in TranslatorRegistry) from translation.targetLanguage; {content} per request.
    // This makes the target language unified across all prompt-driven backends (CLI + openai-http/anthropic-http).
    public const string DefaultPromptTemplate =
        "源语言为英文时,专业术语/技术名词保留英文,其余描述性内容译为{target}。\n" +
        "源语言为非英文时,全部译为{target}(含代码注释、变量名解释)。\n" +
        "代码块、命令行、配置示例保持原样,仅翻译其中说明性文字。只输出译文,不要任何前后缀。\n\n" +
        "内容:\n{content}";

    /// <summary>The pre-{target} default. Existing configs still carrying it are auto-upgraded to
    /// <see cref="DefaultPromptTemplate"/> on load so the new unified target language takes effect.</summary>
    public const string OldPromptTemplate =
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
            TargetLanguage = "简体中文",
            TargetLanguageDefault = "zh-CN",
            MaxChars = 8000,
            PromptTemplate = DefaultPromptTemplate
        },
        Backends = new Dictionary<string, BackendConfig>
        {
            ["claude"]  = new() { Type = "cli", Command = "claude", Model = "haiku", OutputFormat = "text", TimeoutSec = 60 },
            ["codex"]   = new() { Type = "cli", Command = "codex", Model = "gpt-5.4-mini", Reasoning = "low", TimeoutSec = 60 },
            ["copilot"] = new() { Type = "cli", Command = "copilot", Model = "auto", TimeoutSec = 60 },
            ["agy"]     = new() { Type = "cli", Command = "agy", Model = "gemini-3.5-flash", FallbackCommand = "gemini", TimeoutSec = 60 },
            ["google-v2"] = new() { Type = "http", Endpoint = "https://translation.googleapis.com/language/translate/v2", ApiKey = "", Target = "zh-CN", Source = "", Format = "text" },
            ["doubao"]  = new() { Type = "http", Endpoint = "https://ark.cn-beijing.volces.com/api/v3/responses", ApiKey = "", Model = "doubao-seed-translation-250915", TargetLanguage = "zh", SourceLanguage = "" },
            ["opencode"] = new() { Type = "cli", Command = "opencode", Model = "deepseek/deepseek-chat", TimeoutSec = 60 },
            ["kimi"]     = new() { Type = "cli", Command = "kimi", Model = "kimi-code/kimi-for-coding", OutputFormat = "stream-json", TimeoutSec = 90 },
            ["mimo"]     = new() { Type = "cli", Command = "mimo", Model = "xiaomi/mimo-v2.5-pro", TimeoutSec = 90 }
        },
        ModelCatalog = new Dictionary<string, List<string>>
        {
            ["claude"]  = new() { "haiku", "sonnet", "opus", "fable" },
            ["codex"]   = new() { "gpt-5.4-mini", "gpt-5.4", "gpt-5.5" },
            ["copilot"] = new() { "auto", "gpt-5.2", "gpt-5-mini", "claude-sonnet-4.5" },
            ["agy"]     = new() { "gemini-3.5-flash", "gemini-3.1-pro" },
            ["google-v2"] = new() { "nmt" },
            ["doubao"]  = new() { "doubao-seed-translation-250915" },
            ["opencode"] = new() { "deepseek/deepseek-chat", "deepseek/deepseek-reasoner", "deepseek/deepseek-v4-pro", "tokenbox/glm-5.2", "tokenbox/kimi-k2.6", "xiaomi-token-plan-cn/mimo-v2.5-pro" },
            ["kimi"]     = new() { "kimi-code/kimi-for-coding" },
            ["mimo"]     = new() { "mimo/mimo-auto", "xiaomi/mimo-v2-flash", "xiaomi/mimo-v2-pro", "xiaomi/mimo-v2.5", "xiaomi/mimo-v2.5-pro" }
        }
    };
}

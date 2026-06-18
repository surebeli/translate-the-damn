import Foundation

/// Owns `config.json` (load/save/default). The default is the hardcoded first-run bootstrap (spec §7);
/// when the file is absent the app writes this exact shape and thereafter the settings UI only
/// reads/writes the file.
public enum ConfigService {
    /// The hardcoded default prompt template (spec §5).
    public static let defaultPromptTemplate =
        "源语言为英文时,专业术语/技术名词保留英文,其余描述性内容译为简体中文。\n" +
        "源语言为非英文时,全部译为简体中文(含代码注释、变量名解释)。\n" +
        "代码块、命令行、配置示例保持原样,仅翻译其中说明性文字。只输出译文,不要任何前后缀。\n\n" +
        "内容:\n{content}"

    /// Default filesystem path for the user config file (`~/.translatethedamn/config.json`).
    public static let defaultConfigPath = "~/.translatethedamn/config.json"

    /// Returns the full first-run default configuration (spec §7).
    public static func defaultConfig() -> AppConfig {
        AppConfig(
            version: 1,
            general: GeneralConfig(
                listenClipboard: true,
                activeBackend: "claude",
                startWithWindows: false
            ),
            hotkey: HotkeyConfig(
                translate: "Ctrl+Alt+T",
                toggleListen: ""
            ),
            popup: PopupConfig(
                style: "acrylic",
                autoDismissSeconds: 6,
                keepOnHover: true,
                position: "top-center"
            ),
            translation: TranslationConfig(
                targetLanguageDefault: "zh-CN",
                maxChars: 8000,
                promptTemplate: defaultPromptTemplate
            ),
            backends: [
                "claude": BackendConfig(
                    type: "cli",
                    command: "claude",
                    model: "haiku",
                    outputFormat: "text",
                    timeoutSec: 30
                ),
                "codex": BackendConfig(
                    type: "cli",
                    command: "codex",
                    model: "gpt-5.4-mini",
                    reasoning: "low",
                    timeoutSec: 30
                ),
                "copilot": BackendConfig(
                    type: "cli",
                    command: "copilot",
                    model: "claude-haiku-4.5",
                    timeoutSec: 30
                ),
                "agy": BackendConfig(
                    type: "cli",
                    command: "agy",
                    model: "gemini-3.5-flash",
                    fallbackCommand: "gemini",
                    timeoutSec: 30
                ),
                "google-v2": BackendConfig(
                    type: "http",
                    endpoint: "https://translation.googleapis.com/language/translate/v2",
                    target: "zh-CN",
                    format: "text"
                ),
                "doubao": BackendConfig(
                    type: "http",
                    model: "doubao-seed-translation-250915",
                    endpoint: "https://ark.cn-beijing.volces.com/api/v3/responses",
                    targetLanguage: "zh"
                )
            ],
            modelCatalog: [
                "claude": ["haiku", "sonnet", "opus", "fable"],
                "codex": ["gpt-5.4-mini", "gpt-5.4", "gpt-5.5"],
                "copilot": ["claude-haiku-4.5", "claude-sonnet-4.6", "gpt-5.4", "gemini-3.5-flash"],
                "agy": ["gemini-3.5-flash", "gemini-3.1-pro"],
                "google-v2": ["nmt"],
                "doubao": ["doubao-seed-translation-250915"]
            ]
        )
    }

    /// Loads an `AppConfig` from the given path. Returns `nil` when the file is absent.
    /// If the file exists but cannot be decoded it is renamed to `<path>.bak` (preserves user
    /// data) and `defaultConfig()` is returned. On success, the result is deep-merged with
    /// defaults so that empty backends/modelCatalog collections are filled.
    public static func load(from path: String) -> AppConfig? {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        guard let data = FileManager.default.contents(atPath: expanded) else { return nil }

        guard let loaded = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            let bakPath = expanded + ".bak"
            try? FileManager.default.moveItem(atPath: expanded, toPath: bakPath)
            fputs("ConfigService: corrupt config moved to \(bakPath)\n", stderr)
            return defaultConfig()
        }

        return ensureDefaults(loaded)
    }

    private static func ensureDefaults(_ loaded: AppConfig) -> AppConfig {
        let defaults = defaultConfig()
        var translation = loaded.translation
        if translation.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            translation.promptTemplate = defaultPromptTemplate
        }
        return AppConfig(
            version: loaded.version,
            general: loaded.general,
            hotkey: loaded.hotkey,
            popup: loaded.popup,
            translation: translation,
            backends: loaded.backends.isEmpty ? defaults.backends : loaded.backends,
            modelCatalog: loaded.modelCatalog.isEmpty ? defaults.modelCatalog : loaded.modelCatalog
        )
    }

    /// Encodes `cfg` with the canonical config encoder and writes it to `path`, creating the parent directory if needed.
    public static func save(_ cfg: AppConfig, to path: String) throws {
        let expanded = (path as NSString).expandingTildeInPath
        let data = try ConfigEncoding.encoder.encode(cfg)
        let url = URL(fileURLWithPath: expanded)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: url, options: .atomic)
    }
}

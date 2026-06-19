import Foundation

/// Strongly-typed view of `~/.translatethedamn/config.json` — the single source of truth (spec §7,
/// Constitution Law 4: config schema is sacred). Mirrors the Windows `AppConfig` shape so the
/// serialized JSON is byte-aligned across platforms.
///
/// JSON encoding is **camelCase with nulls omitted** (Constitution Law 5). We achieve this with the
/// default `JSONEncoder` (no `keyEncodingStrategy`) — Swift CodingKeys are already camelCase — and
/// by making every heterogenous backend field `Optional` so absent values are dropped, not emitted
/// as JSON null. This matches `conformance/config-defaults.json` paths like `backends.claude.model`
/// and the requirement that empty `source`/`sourceLanguage` be omitted entirely.
public struct AppConfig: Codable {
    public var version: Int
    public var general: GeneralConfig
    public var hotkey: HotkeyConfig
    public var popup: PopupConfig
    public var translation: TranslationConfig
    public var backends: [String: BackendConfig]
    public var modelCatalog: [String: [String]]

    public init(
        version: Int = 1,
        general: GeneralConfig = .init(),
        hotkey: HotkeyConfig = .init(),
        popup: PopupConfig = .init(),
        translation: TranslationConfig = .init(),
        backends: [String: BackendConfig] = [:],
        modelCatalog: [String: [String]] = [:]
    ) {
        self.version = version
        self.general = general
        self.hotkey = hotkey
        self.popup = popup
        self.translation = translation
        self.backends = backends
        self.modelCatalog = modelCatalog
    }
}

public struct GeneralConfig: Codable {
    public var listenClipboard: Bool
    public var activeBackend: String
    public var startWithWindows: Bool
    public var uiStyle: String?  // Vestigial: the macOS port consolidated to a single UI, so this is no longer read. Kept (nil-by-default) only for back-compat with older config.json — serialized config (conformance) stays unchanged.

    public init(listenClipboard: Bool = true, activeBackend: String = "claude", startWithWindows: Bool = false, uiStyle: String? = nil) {
        self.listenClipboard = listenClipboard
        self.activeBackend = activeBackend
        self.startWithWindows = startWithWindows
        self.uiStyle = uiStyle
    }
}

public struct HotkeyConfig: Codable {
    public var translate: String
    public var toggleListen: String

    public init(translate: String = "Ctrl+Alt+T", toggleListen: String = "") {
        self.translate = translate
        self.toggleListen = toggleListen
    }
}

public struct PopupConfig: Codable {
    public var style: String        // "acrylic" | "solid"
    public var autoDismissSeconds: Int
    public var keepOnHover: Bool
    public var position: String

    public init(style: String = "solid", autoDismissSeconds: Int = 6, keepOnHover: Bool = true, position: String = "top-center") {
        self.style = style
        self.autoDismissSeconds = autoDismissSeconds
        self.keepOnHover = keepOnHover
        self.position = position
    }
}

public struct TranslationConfig: Codable {
    public var targetLanguageDefault: String
    public var maxChars: Int
    public var promptTemplate: String

    public init(targetLanguageDefault: String = "zh-CN", maxChars: Int = 8000, promptTemplate: String = "") {
        self.targetLanguageDefault = targetLanguageDefault
        self.maxChars = maxChars
        self.promptTemplate = promptTemplate
    }
}

/// Per-backend settings. Heterogeneous across cli vs http backends, so every backend-specific field
/// is optional; `type` disambiguates. The serialized form omits absent optionals (no JSON null),
/// matching the spec §7 example exactly.
public struct BackendConfig: Codable {
    public var type: String                 // "cli" | "http"

    // --- cli ---
    public var command: String?
    public var model: String?
    public var reasoning: String?
    public var outputFormat: String?
    public var fallbackCommand: String?
    public var timeoutSec: Int?

    // --- http ---
    public var endpoint: String?
    public var apiKey: String?
    public var target: String?              // google-v2
    public var source: String?              // google-v2
    public var format: String?              // google-v2
    public var targetLanguage: String?      // doubao
    public var sourceLanguage: String?      // doubao

    public init(
        type: String = "cli",
        command: String? = nil,
        model: String? = nil,
        reasoning: String? = nil,
        outputFormat: String? = nil,
        fallbackCommand: String? = nil,
        timeoutSec: Int? = nil,
        endpoint: String? = nil,
        apiKey: String? = nil,
        target: String? = nil,
        source: String? = nil,
        format: String? = nil,
        targetLanguage: String? = nil,
        sourceLanguage: String? = nil
    ) {
        self.type = type
        self.command = command
        self.model = model
        self.reasoning = reasoning
        self.outputFormat = outputFormat
        self.fallbackCommand = fallbackCommand
        self.timeoutSec = timeoutSec
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.target = target
        self.source = source
        self.format = format
        self.targetLanguage = targetLanguage
        self.sourceLanguage = sourceLanguage
    }

    public var isHttp: Bool { type.lowercased() == "http" }
}

/// JSON encoder for config.json: camelCase, nulls omitted, sorted keys for deterministic output.
public enum ConfigEncoding {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // No keyEncodingStrategy — CodingKeys are already camelCase. Optionals encode as absent
        // (not null) by default, which is exactly the "nulls omitted" contract.
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

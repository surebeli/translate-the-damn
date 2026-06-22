import Foundation

/// A built HTTP request (pure, testable): method, url, headers, and the JSON body string. Mirrors the
/// Windows `HttpCall` record. Pinned by `conformance/backend-requests.json` (method/url/headers/body).
public struct HttpCall: Equatable {
    public var method: String
    public var url: String
    public var headers: [String: String]
    public var body: String

    public init(method: String = "", url: String = "", headers: [String: String] = [:], body: String = "") {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// The typed slice of a backend config that the `backend-requests` conformance vector feeds into
/// `buildCall`. The real M2 interpreter will read `spec/backends.json` (Constitution Law 6) + the
/// full `BackendConfig`; M1 only needs the request-shape inputs the vector pins. All fields optional
/// because the vector omits keys per-case (e.g. google-v2 omits `source` to assert auto-detect).
public struct BackendTestConfig: Codable {
    public var apiKey: String?
    public var target: String?
    public var source: String?
    public var format: String?
    public var model: String?
    public var targetLanguage: String?
    public var endpoint: String?
    public var sourceLanguage: String?

    public init(
        apiKey: String? = nil,
        target: String? = nil,
        source: String? = nil,
        format: String? = nil,
        model: String? = nil,
        targetLanguage: String? = nil,
        endpoint: String? = nil,
        sourceLanguage: String? = nil
    ) {
        self.apiKey = apiKey
        self.target = target
        self.source = source
        self.format = format
        self.model = model
        self.targetLanguage = targetLanguage
        self.endpoint = endpoint
        self.sourceLanguage = sourceLanguage
    }
}

/// Builds the HTTP request for the dedicated translation APIs (google-v2, doubao) from a backend id
/// + config + text. Pure and testable; the network round-trip lives in the App layer (M3).
///
/// Reads `spec/backends.json` at runtime (Constitution Law 6): method, url, headers, and body are
/// all driven by the declarative manifest. Placeholders in headers and bodyTemplate are substituted
/// from config. `omitWhenEmpty` keys with empty values are dropped. Config values that are nil or
/// empty fall back to manifest `defaults`.
public enum HttpBackend {
    public static func buildCall(backend: String, config: BackendTestConfig, text: String, promptTemplate: String = "") -> HttpCall {
        guard let def = BackendManifest.backendDef(backend) else {
            return HttpCall()
        }

        let vars: [String: String] = [
            "text": text,
            // {prompt} = the full built translation prompt (rules + text), as the CLI backends send.
            // Distinct from PromptBuilder's own {content} placeholder. Unused by google-v2/doubao.
            "prompt": PromptBuilder.build(template: promptTemplate, content: text),
            "apiKey": config.apiKey ?? "",
            "model": pick(cfg: config.model, key: "model", def: def),
            "target": pick(cfg: config.target, key: "target", def: def),
            "format": pick(cfg: config.format, key: "format", def: def),
            "targetLanguage": pick(cfg: config.targetLanguage, key: "targetLanguage", def: def),
            "source": config.source ?? "",
            "sourceLanguage": config.sourceLanguage ?? "",
        ]

        let method = def["method"] as? String ?? "POST"
        // Prefer the config endpoint over the manifest's (empty for openai-http/anthropic-http); then
        // chatPath-normalize a BASE endpoint (e.g. .../v1 -> .../v1/chat/completions), matching the
        // @ai-sdk/openai-compatible convention. Mirrors Windows ManifestHttpBackend.Endpoint.
        var url = (config.endpoint?.isEmpty == false) ? config.endpoint! : (def["endpoint"] as? String ?? "")
        if let chatPath = def["chatPath"] as? String, !chatPath.isEmpty, !url.isEmpty {
            let trimmed = url.hasSuffix("/") ? String(url.dropLast()) : url
            if !trimmed.lowercased().hasSuffix(chatPath.lowercased()) { url = trimmed + chatPath }
        }

        var headers: [String: String] = [:]
        if let manifestHeaders = def["headers"] as? [String: String] {
            for (k, v) in manifestHeaders {
                headers[k] = BackendManifest.subst(v, vars)
            }
        }

        let omitSet = Set(def["omitWhenEmpty"] as? [String] ?? [])
        let bodyTemplate = def["bodyTemplate"] as Any
        let body = BackendManifest.buildBody(template: bodyTemplate, vars: vars, omitWhenEmpty: omitSet)

        return HttpCall(method: method, url: url, headers: headers, body: body)
    }

    private static func pick(cfg: String?, key: String, def: [String: Any]) -> String {
        if let v = cfg, !v.isEmpty { return v }
        return BackendManifest.defaultString(def, key) ?? ""
    }
}

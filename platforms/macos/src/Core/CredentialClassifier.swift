import Foundation

/// A STATIC API credential discovered on the local machine, ready to import as an http backend.
/// Mirrors the Windows `DiscoveredCredential`. `key` is the real secret — never log it; the UI shows `keyMasked`.
public struct DiscoveredCredential: Equatable {
    public let source: String       // provenance, e.g. "env:DEEPSEEK_API_KEY" or a config file path
    public let provider: String     // display name, e.g. "DeepSeek"
    public let suggestedId: String  // backend id to create, e.g. "deepseek"
    public let baseUrl: String      // canonical base (chat suffix stripped)
    public let protocolName: String // "openai" | "anthropic"
    public let keyMasked: String    // prefix + length for the UI
    public let key: String          // the actual secret — NEVER log
}

/// Pure classifier: turns a (source, baseUrl, key) tuple into an importable credential, or nil to SKIP.
/// The static-key/OAuth boundary is the security contract — pinned by `conformance/credential-discovery.json`.
/// Mirrors the Windows `CredentialClassifier` exactly so the shared vector passes on both platforms.
public enum CredentialClassifier {
    private static let subscriptionHosts: Set<String> = [
        "api.anthropic.com", "claude.ai",
        "generativelanguage.googleapis.com", "cloudcode-pa.googleapis.com", "oauth2.googleapis.com", "accounts.google.com",
        "api.githubcopilot.com", "github.com",
    ]

    public static func classify(source: String, baseUrl: String?, key: String?) -> DiscoveredCredential? {
        guard let key = key, !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let baseUrl = baseUrl, !baseUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        if looksLikeOAuthToken(key) { return nil }
        guard let host = hostOf(baseUrl) else { return nil }
        if subscriptionHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return nil }

        let (provider, proto, id, normBase) = mapHost(host, baseUrl)
        return DiscoveredCredential(
            source: source, provider: provider, suggestedId: id, baseUrl: normBase,
            protocolName: proto, keyMasked: mask(key), key: key.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// True for refreshing/client-bound OAuth tokens that are NOT importable static keys.
    public static func looksLikeOAuthToken(_ key: String) -> Bool {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { return false }
        if k.hasPrefix("eyJ") { return true }              // JWT access_token
        if k.hasPrefix("ya29.") { return true }            // Google OAuth access_token
        if k.hasPrefix("1//") { return true }              // Google refresh token
        if k.hasPrefix("gho_") || k.hasPrefix("ghu_") { return true }  // GitHub
        if k.count > 300 { return true }                   // OAuth tokens are long; static API keys aren't
        return false
    }

    private static func mapHost(_ host: String, _ baseUrl: String) -> (String, String, String, String) {
        if host == "api.deepseek.com" { return ("DeepSeek", "openai", "deepseek", "https://api.deepseek.com/v1") }
        if host == "api.moonshot.ai" || host == "api.moonshot.cn" { return ("Moonshot", "openai", "moonshot", "https://api.moonshot.ai/v1") }
        if host == "api.kimi.com" { return ("Kimi Code", "anthropic", "kimi-code", "https://api.kimi.com/coding/v1") }
        if host == "api.xiaomimimo.com" { return ("Xiaomi MiMo", "openai", "mimo", "https://api.xiaomimimo.com/v1") }
        if host.hasSuffix(".xiaomimimo.com") { return ("Xiaomi MiMo Token-Plan", "openai", "mimo-token-plan", trimToBase(baseUrl)) }
        if host == "tokbox-api.netease.im" { return ("tokenbox", "openai", "tokenbox", "https://tokbox-api.netease.im/v1") }
        if host == "openrouter.ai" { return ("OpenRouter", "openai", "openrouter", "https://openrouter.ai/api/v1") }
        if host == "api.openai.com" { return ("OpenAI", "openai", "openai", "https://api.openai.com/v1") }
        // Unknown host: import as a generic OpenAI-compatible provider (user reviews + confirms).
        return (host, "openai", host.replacingOccurrences(of: ".", with: "-"), trimToBase(baseUrl))
    }

    private static func trimToBase(_ url: String) -> String {
        var u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if u.hasSuffix("/") { u = String(u.dropLast()) }
        for tail in ["/chat/completions", "/messages", "/responses", "/completions"] where u.lowercased().hasSuffix(tail) {
            return String(u.dropLast(tail.count))
        }
        return u
    }

    private static func hostOf(_ url: String) -> String? {
        let full = url.contains("://") ? url : "https://" + url
        return URL(string: full)?.host?.lowercased()
    }

    /// Prefix + length only — never the full secret.
    public static func mask(_ key: String) -> String {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = k.count <= 8 ? k : String(k.prefix(8))
        return "\(prefix)…(\(k.count))"
    }
}

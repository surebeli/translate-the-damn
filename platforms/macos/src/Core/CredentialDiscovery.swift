import Foundation

/// Read-only scanner: discovers user-owned STATIC keys from env vars + opencode (auth.json/opencode.json)
/// + codex (config.toml). cc-switch SQLite deferred. Never writes; never reads OAuth stores. The
/// static-key/OAuth boundary lives in `CredentialClassifier` (conformance-pinned). Mirrors Windows.
public enum CredentialDiscovery {
    private static let envProviders: [(env: String, baseUrl: String)] = [
        ("DEEPSEEK_API_KEY",   "https://api.deepseek.com/v1"),
        ("MOONSHOT_API_KEY",   "https://api.moonshot.ai/v1"),
        ("MIMO_API_KEY",       "https://api.xiaomimimo.com/v1"),
        ("OPENROUTER_API_KEY", "https://openrouter.ai/api/v1"),
        ("GROQ_API_KEY",       "https://api.groq.com/openai/v1"),
    ]
    // opencode auth.json stores only the key — map its provider id to the base URL.
    private static let opencodeProviderBase: [String: String] = [
        "deepseek": "https://api.deepseek.com/v1",
        "moonshot": "https://api.moonshot.ai/v1",
        "kimi-code": "https://api.kimi.com/coding/v1",
        "xiaomi": "https://api.xiaomimimo.com/v1",
        "xiaomi-token-plan-cn": "https://token-plan-cn.xiaomimimo.com/v1",
        "openrouter": "https://openrouter.ai/api/v1",
        "groq": "https://api.groq.com/openai/v1",
    ]

    public static func scan(home: String? = nil) -> [DiscoveredCredential] {
        let profile = home ?? NSHomeDirectory()
        var raw: [(source: String, baseUrl: String, key: String)] = []
        raw.append(contentsOf: fromEnv())
        raw.append(contentsOf: fromOpencodeAuth(profile + "/.local/share/opencode/auth.json"))
        raw.append(contentsOf: fromOpencodeConfig(profile + "/.config/opencode/opencode.json"))
        raw.append(contentsOf: fromCodexToml(profile + "/.codex/config.toml"))

        var seen = Set<String>()
        var found: [DiscoveredCredential] = []
        for item in raw {
            guard let c = CredentialClassifier.classify(source: item.source, baseUrl: item.baseUrl, key: item.key) else { continue }
            let host = URL(string: c.baseUrl)?.host?.lowercased() ?? c.baseUrl
            let dedup = host + "|" + c.key
            if !seen.contains(dedup) { seen.insert(dedup); found.append(c) }
        }
        return found
    }

    private static func env(_ name: String) -> String? {
        let v = ProcessInfo.processInfo.environment[name]
        return (v?.isEmpty ?? true) ? nil : v
    }

    private static func fromEnv() -> [(String, String, String)] {
        var out: [(String, String, String)] = []
        for p in envProviders where env(p.env) != nil { out.append(("env:\(p.env)", p.baseUrl, env(p.env)!)) }
        if let ok = env("OPENAI_API_KEY") {
            out.append(("env:OPENAI_API_KEY", env("OPENAI_BASE_URL") ?? "https://api.openai.com/v1", ok))
        }
        return out
    }

    private static func fromOpencodeAuth(_ path: String) -> [(String, String, String)] {
        guard let data = FileManager.default.contents(atPath: path),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        var out: [(String, String, String)] = []
        for (provider, val) in root {
            guard let obj = val as? [String: Any],
                  (obj["type"] as? String)?.lowercased() == "api",          // skip oauth entries
                  let key = obj["key"] as? String, !key.isEmpty,
                  let base = opencodeProviderBase[provider] else { continue }
            out.append(("opencode:auth.json:\(provider)", base, key))
        }
        return out
    }

    private static func fromOpencodeConfig(_ path: String) -> [(String, String, String)] {
        guard let data = FileManager.default.contents(atPath: path),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let provs = root["provider"] as? [String: Any] else { return [] }
        var out: [(String, String, String)] = []
        for (name, val) in provs {
            guard let obj = val as? [String: Any], let opts = obj["options"] as? [String: Any],
                  let base = opts["baseURL"] as? String, !base.isEmpty,
                  let key = opts["apiKey"] as? String, !key.isEmpty else { continue }
            out.append(("opencode:opencode.json:\(name)", base, key))
        }
        return out
    }

    // Minimal codex config.toml reader: [model_providers.<id>] base_url + env_key (the key is in the named env var).
    private static func fromCodexToml(_ path: String) -> [(String, String, String)] {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        var out: [(String, String, String)] = []
        var id: String?
        var baseUrl: String?
        var envKey: String?
        func flush() {
            if let id = id, let b = baseUrl, let e = envKey, let k = env(e) {
                out.append(("codex:config.toml:\(id)", b, k))
            }
            baseUrl = nil; envKey = nil
        }
        for line in content.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[") {
                flush()
                if t.lowercased().hasPrefix("[model_providers.") {
                    id = String(t.dropFirst().dropLast())
                        .replacingOccurrences(of: "model_providers.", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                } else {
                    id = nil
                }
            } else if id != nil {
                if let v = tomlValue(t, "base_url") { baseUrl = v }
                if let v = tomlValue(t, "env_key") { envKey = v }
            }
        }
        flush()
        return out
    }

    private static func tomlValue(_ line: String, _ key: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix(key), let eq = t.firstIndex(of: "=") else { return nil }
        return String(t[t.index(after: eq)...])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}

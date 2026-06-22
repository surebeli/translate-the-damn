import Foundation

public enum BackendManifest {
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var _cachedManifest: [String: Any]?

    public static func load() -> [String: Any] {
        cacheLock.lock()
        if let c = _cachedManifest {
            cacheLock.unlock()
            return c
        }

        // In a .app bundle, #file resolves to a short module path that doesn't walk up
        // to the repo root. Try Bundle.main (the bundled backends.json resource) first.
        if let bundleURL = Bundle.main.url(forResource: "backends", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            _cachedManifest = obj
            cacheLock.unlock()
            return obj
        }

        var url = URL(fileURLWithPath: #file).deletingLastPathComponent()
        while url.path != "/" {
            let candidate = url.appendingPathComponent("spec/backends.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                if let data = try? Data(contentsOf: candidate),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                {
                    _cachedManifest = obj
                    cacheLock.unlock()
                    return obj
                }
                fputs("BackendManifest: failed to parse \(candidate.path)\n", stderr)
                let empty: [String: Any] = ["backends": [:]]
                _cachedManifest = empty
                cacheLock.unlock()
                return empty
            }
            url = url.deletingLastPathComponent()
        }
        fputs("BackendManifest: cannot find spec/backends.json by walking up from \(#file)\n", stderr)
        let empty: [String: Any] = ["backends": [:]]
        _cachedManifest = empty
        cacheLock.unlock()
        return empty
    }

    public static func backendDef(_ id: String) -> [String: Any]? {
        let manifest = load()
        guard let backends = manifest["backends"] as? [String: Any] else { return nil }
        if let def = backends[id] as? [String: Any] { return def }
        return (backends[id.lowercased()] as? [String: Any])
    }

    public static func defaultString(_ def: [String: Any]?, _ key: String) -> String? {
        guard let defaults = def?["defaults"] as? [String: String] else { return nil }
        return defaults[key]
    }

    /// Per-CLI-backend effort/reasoning tiers declared in `spec/backends.json` — drives the
    /// per-vendor effort selector. An absent `effortTiers` key (e.g. agy/kimi: effort is a model-label
    /// suffix or always-on, no flag) → empty list. Mirrors the shared `effort-tiers` conformance
    /// vector; every platform's interpreter must expose the same lists from the shared manifest.
    public static func effortTiers(_ backend: String) -> [String] {
        guard let def = backendDef(backend),
              let tiers = def["effortTiers"] as? [Any] else { return [] }
        return tiers.compactMap { $0 as? String }
    }

    /// The declarative doctor probe for a backend, straight from `spec/backends.json` (Law 6) —
    /// `{ args | kind, network, retries, successSignatures, failSignatures, failWins, credFiles }`.
    /// nil when the backend declares no probe (e.g. copilot: presence-only). The doctor runs `args`
    /// (or checks `credFiles` for `kind:"log"`) and feeds the output to `ProbeClassifier`. Mirrors the
    /// shared `doctor-probe` vector — every platform exposes the same probe from the shared manifest.
    public static func probe(_ backend: String) -> [String: Any]? {
        backendDef(backend)?["probe"] as? [String: Any]
    }

    public static func subst(_ template: String, _ vars: [String: String]) -> String {
        var result = ""
        var i = template.startIndex
        while i < template.endIndex {
            guard let open = template[i...].firstIndex(of: "{") else {
                result += template[i...]
                break
            }
            guard let close = template[open...].firstIndex(of: "}") else {
                result += template[i...]
                break
            }
            result += template[i..<open]
            let name = String(template[template.index(after: open)..<close])
            result += vars[name] ?? ""
            i = template.index(after: close)
        }
        return result
    }

    public static func buildBody(template: Any, vars: [String: String], omitWhenEmpty: Set<String>) -> String {
        let result = buildValue(template, vars: vars, omitWhenEmpty: omitWhenEmpty)
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: []) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func buildValue(_ value: Any, vars: [String: String], omitWhenEmpty: Set<String>) -> Any {
        switch value {
        case let dict as [String: Any]:
            var result = [String: Any]()
            for (key, val) in dict {
                let child = buildValue(val, vars: vars, omitWhenEmpty: omitWhenEmpty)
                if omitWhenEmpty.contains(key) && isEmptyStringValue(child) {
                    continue
                }
                result[key] = child
            }
            return result
        case let arr as [Any]:
            return arr.map { buildValue($0, vars: vars, omitWhenEmpty: omitWhenEmpty) }
        case let str as String:
            return subst(str, vars)
        default:
            return value
        }
    }

    private static func isEmptyStringValue(_ value: Any) -> Bool {
        return (value as? String)?.isEmpty ?? false
    }

    public static func eval(root: Any, path: String) -> String? {
        var cur: Any = root
        for rawSeg in path.split(separator: ".") {
            var seg = String(rawSeg)
            var bracket: String?

            if let lb = seg.firstIndex(of: "["),
               let rb = seg[lb...].firstIndex(of: "]")
            {
                bracket = String(seg[seg.index(after: lb)..<rb])
                seg = String(seg[..<lb])
            }

            if !seg.isEmpty {
                guard let obj = cur as? [String: Any],
                      let next = obj[seg]
                else { return nil }
                cur = next
            }

            if let bracket = bracket {
                guard let arr = cur as? [Any] else { return nil }
                if let eq = bracket.firstIndex(of: "=") {
                    let key = String(bracket[..<eq])
                    let value = String(bracket[bracket.index(after: eq)...])
                    var found = false
                    for el in arr {
                        if let obj = el as? [String: Any],
                           let kv = obj[key] as? String,
                           kv == value
                        {
                            cur = el
                            found = true
                            break
                        }
                    }
                    if !found { return nil }
                } else if let idx = Int(bracket), idx >= 0, idx < arr.count {
                    cur = arr[idx]
                } else {
                    return nil
                }
            }
        }
        return cur as? String
    }
}

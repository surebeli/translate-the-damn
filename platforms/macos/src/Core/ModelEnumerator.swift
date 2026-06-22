import Foundation

/// Generic LIVE model enumeration: `GET <provider>/models` (derived from the chat endpoint), parsed
/// across the common shapes. Mirrors the Windows `ModelEnumerator`. The pure helpers (`deriveModelsUrls`,
/// `parseModelsJson`) are unit-tested; the HTTP fetch is best-effort — any failure returns `[]` so the
/// caller keeps the static catalog. Sends the user's own key to the user's own provider; never logs it.
public enum ModelEnumerator {
    /// Fetch the model ids for an HTTP/API backend. Empty on any failure.
    public static func enumerate(endpoint: String?, apiKey: String?, protocolName: String?, timeout: Int = 10) -> [String] {
        guard let endpoint = endpoint, !endpoint.trimmingCharacters(in: .whitespaces).isEmpty,
              let apiKey = apiKey, !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
        else { return [] }
        let anthropic = (protocolName ?? "").trimmingCharacters(in: .whitespaces).lowercased() == "anthropic"

        for urlStr in deriveModelsUrls(endpoint) {
            guard let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")  // works for deepseek/kimi/anthropic relays
            if anthropic {
                req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
            req.timeoutInterval = TimeInterval(max(timeout, 1))

            var resultData: Data?
            var status = 0
            let sem = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                resultData = data
                status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                sem.signal()
            }.resume()
            _ = sem.wait(timeout: .now() + .seconds(max(timeout, 1) + 2))

            guard status == 200, let data = resultData else { continue }
            let models = parseModelsJson(data)
            if !models.isEmpty { return models }
        }
        return []
    }

    /// Candidate `/models` URLs for any chat/messages/base endpoint, tried in order. Prefers a versioned
    /// `/v1/models` for a version-less base (relays serve `/v1/models`, not `/models`). Pure + public for tests.
    public static func deriveModelsUrls(_ endpoint: String) -> [String] {
        var urls: [String] = []
        let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return urls }
        func add(_ u: String) {
            if !u.isEmpty && !urls.contains(where: { $0.caseInsensitiveCompare(u) == .orderedSame }) { urls.append(u) }
        }
        var e = trimmed
        if e.hasSuffix("/") { e = String(e.dropLast()) }

        // Recover the API root by stripping a known chat/models tail.
        var root = e
        for tail in ["/chat/completions", "/messages", "/responses", "/completions"] where root.lowercased().hasSuffix(tail) {
            root = String(root.dropLast(tail.count)); break
        }
        if root.lowercased().hasSuffix("/models") { root = String(root.dropLast("/models".count)) }

        let hasVersion = root.range(of: "/v[0-9]", options: .regularExpression) != nil
        if hasVersion { add(root + "/models") } else { add(root + "/v1/models"); add(root + "/models") }

        if let u = URL(string: e), let scheme = u.scheme, let host = u.host {
            let authority = "\(scheme)://\(host)" + (u.port.map { ":\($0)" } ?? "")
            add(authority + "/v1/models"); add(authority + "/models")
        }
        return urls
    }

    /// Live-enumerate a CLI backend's models by running its manifest `modelsCmd` (e.g. `mimo models`,
    /// `opencode models`) from the neutral sandbox and parsing provider/name lines. Returns [] on ANY
    /// failure (no `modelsCmd`, unresolved binary, non-zero exit, timeout) — the caller falls back to
    /// the static catalog. Mirrors the Windows `ModelEnumerator` CLI branch (Constitution Law 6: the
    /// subcommand is manifest-declared, no per-vendor code).
    public static func enumerateCli(backendId: String, command: String?,
                                    runner: ProcessRunner = ProcessRunner(),
                                    pathResolver: PathResolver = PathResolver(), timeoutSec: Int = 15) -> [String] {
        guard let def = BackendManifest.backendDef(backendId),
              let modelsCmd = (def["modelsCmd"] as? [Any])?.compactMap({ $0 as? String }), !modelsCmd.isEmpty
        else { return [] }
        let cmd = (command?.isEmpty == false) ? command! : (def["command"] as? String ?? backendId)
        guard let executable = pathResolver.resolve(cmd) else { return [] }
        // Cap at 15s (ceiling, not floor) — enumeration must never hang the settings dialog.
        let ceiling = min(max(timeoutSec * 1000, 3000), 15000)
        let r = runner.run(executable: executable, args: modelsCmd, stdinMode: .empty, stdinText: nil,
                           ceilingMs: ceiling, idleMs: 15000, extraEnv: nil,
                           workingDirectory: NSTemporaryDirectory() + "ttd-sandbox", shouldCancel: nil)
        guard r.exitCode == 0, !r.timedOut, !r.notFound else { return [] }
        return parseModelsList(r.stdout)
    }

    /// Parse a CLI `models` subcommand's stdout: one model id per line, keep `provider/name` ids, drop
    /// blanks, spaced lines, and chrome (no slash). ANSI-stripped, deduped, original order preserved.
    /// Pure + public for tests; mirrors Windows `ModelEnumerator.ParseModels`. Pinned by
    /// `conformance/models-list-parse.json`.
    public static func parseModelsList(_ stdout: String) -> [String] {
        var seen = Set<String>()
        var models: [String] = []
        for line in AnsiStripper.strip(stdout).components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.contains(" ") || !t.contains("/") { continue }  // ids are "provider/name", never spaced
            if seen.insert(t).inserted { models.append(t) }
        }
        return models
    }

    /// Parse a models-list response across the common shapes: OpenAI/Anthropic `{ "data":[{"id"}] }`,
    /// Ollama `{ "models":[{"name"}] }`, or a bare array of strings/objects. Deduped, order-preserved.
    public static func parseModelsJson(_ data: Data) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []
        func tryAdd(_ s: String?) {
            guard let s = s, !s.trimmingCharacters(in: .whitespaces).isEmpty, !seen.contains(s) else { return }
            seen.insert(s); ids.append(s)
        }
        func scan(_ arr: [Any]) {
            for m in arr {
                if let s = m as? String { tryAdd(s); continue }
                guard let obj = m as? [String: Any] else { continue }
                if let v = obj["id"] as? String { tryAdd(v) }
                else if let n = obj["name"] as? String { tryAdd(n) }
                else if let md = obj["model"] as? String { tryAdd(md) }
            }
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let arr = json as? [Any] { scan(arr) }
        else if let obj = json as? [String: Any] {
            for key in ["data", "models"] where obj[key] is [Any] { scan(obj[key] as! [Any]) }
        }
        return ids
    }
}

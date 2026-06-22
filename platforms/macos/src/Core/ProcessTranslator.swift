import Foundation

public final class ProcessTranslator: Translator {
    private let id: String
    private let config: BackendConfig
    private let promptTemplate: String
    private let runner: ProcessRunner
    private let pathResolver: PathResolver

    public init(id: String, config: BackendConfig, promptTemplate: String = "", runner: ProcessRunner = ProcessRunner(), pathResolver: PathResolver = PathResolver()) {
        self.id = id
        self.config = config
        self.promptTemplate = promptTemplate
        self.runner = runner
        self.pathResolver = pathResolver
    }

    public func translate(text: String, model: String) -> TranslationResult {
        let prompt = PromptBuilder.build(template: promptTemplate, content: text)
        let effectiveModel = config.model ?? effectiveDefaultModel()

        let result = runPrimary(prompt: prompt, model: effectiveModel)
        if result.ok { return result }

        let def = BackendManifest.backendDef(id) ?? [:]
        let fbCommand = config.fallbackCommand ?? def["fallbackCommand"] as? String
        if (result.status == .notFound || result.status == .badOutput),
           let fb = fbCommand, !fb.trimmingCharacters(in: .whitespaces).isEmpty {
            let fbResult = runFallback(prompt: prompt, fbCommand: fb, model: effectiveModel, def: def)
            if fbResult.ok { return fbResult }
            return result.status == .notFound ? fbResult : result
        }

        return result
    }

    private func runPrimary(prompt: String, model: String) -> TranslationResult {
        let resolved = resolveCommand(config.command)
        guard let executable = resolved else {
            return .failed(.notFound, "找不到命令 \u{201C}\(config.command ?? id)\u{201D}，请确认已安装并在 PATH 中。")
        }

        let def = BackendManifest.backendDef(id) ?? [:]

        let logFile: String?
        let wantsLogFile = (def["parse"] as? [String: Any])?["mode"] as? String == "stdout-clean"
            && ((def["parse"] as? [String: Any])?["logDiagnosis"] as? String)?.contains("log") == true
        if wantsLogFile {
            logFile = NSTemporaryDirectory() + "ttd-\(id)-\(UUID().uuidString).log"
        } else {
            logFile = nil
        }

        let invocation = buildInvocation(def: def, prompt: prompt, model: model, logFile: logFile)

        let ceilingMs = max(3000, (config.timeoutSec ?? defTimeoutSec(def)) * 1000)

        let result = runner.run(
            executable: executable,
            args: invocation.args,
            stdinMode: invocation.stdinMode,
            stdinText: invocation.stdinText,
            ceilingMs: ceilingMs,
            idleMs: 15000,
            extraEnv: nil,
            workingDirectory: sandboxDirectory(),
            shouldCancel: nil
        )

        if result.notFound {
            return .failed(.notFound, result.failureDetail ?? "命令无法启动")
        }
        if result.timedOut {
            return .failed(.timeout, "翻译超时(\(ceilingMs / 1000)s)")
        }
        if result.cancelled {
            return .failed(.unknownFail, "翻译已取消")
        }

        let parseDef = def["parse"] as? [String: Any]
        _ = parseDef?["mode"] as? String ?? "stdout-clean"

        let cleanedOutput = cleanOutput(result.stdout, def: def)
        if !cleanedOutput.isEmpty {
            return .successful(cleanedOutput)
        }

        var logContent: String?
        if let lf = logFile {
            logContent = try? String(contentsOfFile: lf, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: lf)
        }

        return classifyFailure(result, logContent: logContent, def: def)
    }

    private func runFallback(prompt: String, fbCommand: String, model: String, def: [String: Any]) -> TranslationResult {
        guard let executable = pathResolver.resolve(fbCommand) else {
            return .failed(.notFound, "找不到回退命令 \u{201C}\(fbCommand)\u{201D}。")
        }

        let fbArgsTemplate = def["fallbackArgs"] as? [String] ?? []
        let vars: [String: String] = [
            "model": model,
            "prompt": prompt
        ]
        let fbArgs = fbArgsTemplate.map { BackendManifest.subst($0, vars) }
        let ceilingMs = max(3000, (config.timeoutSec ?? defTimeoutSec(def)) * 1000)

        let fbResult = runner.run(
            executable: executable,
            args: fbArgs,
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: ceilingMs,
            idleMs: 15000,
            extraEnv: nil,
            workingDirectory: sandboxDirectory(),
            shouldCancel: nil
        )

        if fbResult.notFound {
            return .failed(.notFound, fbResult.failureDetail ?? "回退命令无法启动")
        }
        if fbResult.timedOut {
            return .failed(.timeout, "回退翻译超时(\(ceilingMs / 1000)s)")
        }
        if fbResult.cancelled {
            return .failed(.unknownFail, "翻译已取消")
        }

        let cleaned = fbResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.isEmpty {
            return .successful(cleaned)
        }

        return .failed(.badOutput, "回退命令也未返回译文。")
    }

    private func resolveCommand(_ command: String?) -> String? {
        let cmd = command ?? id
        return pathResolver.resolve(cmd)
    }

    private func effectiveDefaultModel() -> String {
        return BackendManifest.defaultString(BackendManifest.backendDef(id), "model") ?? ""
    }

    private func defTimeoutSec(_ def: [String: Any]) -> Int {
        if let s = BackendManifest.defaultString(def, "timeoutSec"), let v = Int(s) {
            return v
        }
        return 60
    }

    private func sandboxDirectory() -> String? {
        return NSTemporaryDirectory() + "ttd-sandbox"
    }

    private struct CliInvocation {
        let args: [String]
        let stdinMode: StdinMode
        let stdinText: String?
    }

    private func buildInvocation(def: [String: Any], prompt: String, model: String, logFile: String?) -> CliInvocation {
        let vars: [String: String] = [
            "model": model,
            "reasoning": config.reasoning ?? BackendManifest.defaultString(def, "reasoning") ?? "",
            "outputFormat": config.outputFormat ?? BackendManifest.defaultString(def, "outputFormat") ?? "text",
            "prompt": prompt,
            "logFile": logFile ?? ""
        ]

        let templateArgs = def["args"] as? [String] ?? []
        let args = templateArgs.map { BackendManifest.subst($0, vars) }

        let promptVia = def["promptVia"] as? String ?? "stdin"
        let stdinMode: StdinMode
        let stdinText: String?

        switch promptVia {
        case "stdin":
            stdinMode = .pipe
            stdinText = prompt
        case "stdin-dash":
            stdinMode = .pipe
            stdinText = prompt
        case "arg":
            stdinMode = .empty
            stdinText = nil
        default:
            stdinMode = .empty
            stdinText = nil
        }

        return CliInvocation(args: args, stdinMode: stdinMode, stdinText: stdinText)
    }

    private func cleanOutput(_ stdout: String, def: [String: Any]) -> String {
        let raw = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        let parseDef = def["parse"] as? [String: Any]
        let outputFormat = config.outputFormat ?? BackendManifest.defaultString(def, "outputFormat") ?? "text"

        if outputFormat.lowercased() == "json",
           let jsonPath = parseDef?["jsonResultPath"] as? String {
            if let data = raw.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = BackendManifest.eval(root: obj, path: jsonPath) {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let jsonEventPath = parseDef?["jsonEvent"] as? String {
            return parseJsonEvent(raw: raw, eventPath: jsonEventPath)
        }

        // stream-json / NDJSON (opencode, mimo, kimi): collect <jsonlTextPath> from lines whose
        // <jsonlTypePath> (default "type") == <jsonlType>. Falls back to raw if nothing matched.
        if parseDef?["jsonl"] as? Bool == true {
            let typeField = parseDef?["jsonlTypePath"] as? String ?? "type"
            let typeValue = parseDef?["jsonlType"] as? String ?? "text"
            let textPath = parseDef?["jsonlTextPath"] as? String ?? "text"
            let collected = BackendManifest.collectJsonl(raw, typeField: typeField, typeValue: typeValue, textPath: textPath)
            return collected.isEmpty ? raw : collected
        }

        return raw
    }

    private func parseJsonEvent(raw: String, eventPath: String) -> String {
        let parts = eventPath.components(separatedBy: " -> ")
        guard parts.count == 2 else { return raw }

        let eventFilter = parts[0]
        let extractPath = parts[1]

        let lines = raw.components(separatedBy: .newlines)
        var lastMatch: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if BackendManifest.eval(root: obj, path: eventFilter) != nil {
                if let extracted = BackendManifest.eval(root: obj, path: extractPath) {
                    lastMatch = extracted
                }
            }
        }

        return (lastMatch ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func classifyFailure(_ result: ProcessResult, logContent: String?, def: [String: Any]) -> TranslationResult {
        let blob = (result.stdout + "\n" + result.stderr + "\n" + (logContent ?? "")).lowercased()

        if looksLikeAuthError(blob) {
            return .failed(.authFail, "认证失败，请在设置中登录或填写密钥。")
        }
        if result.exitCode != 0 {
            let errMsg = firstNonEmptyLine(result.stderr) ?? "退出码 \(result.exitCode)"
            return .failed(.unknownFail, errMsg)
        }

        let parseDef = def["parse"] as? [String: Any]
        if let logDiagnosis = parseDef?["logDiagnosis"] as? String,
           logDiagnosis.contains("auth-error-in-log"),
           let log = logContent?.lowercased(),
           looksLikeAuthError(log) {
            return .failed(.authFail, "认证失败，请在设置中登录或填写密钥。")
        }

        return .failed(.badOutput, "没有返回译文(可能是该 CLI 在 macOS 下的已知输出问题)。")
    }

    private func looksLikeAuthError(_ lowerBlob: String) -> Bool {
        return lowerBlob.contains("not logged in")
            || lowerBlob.contains("unauthorized")
            || lowerBlob.contains("authentication")
            || lowerBlob.contains("auth error")
            || (lowerBlob.contains("please run") && lowerBlob.contains("login"))
            || lowerBlob.contains("api key")
            || lowerBlob.contains(" 401")
    }

    private func firstNonEmptyLine(_ s: String) -> String? {
        for line in s.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { return t }
        }
        return nil
    }
}

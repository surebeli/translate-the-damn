import Foundation

public enum DoctorStatus: String, Sendable {
    case ok          // authenticated / reachable
    case fail        // not authenticated
    case unknown     // ran but couldn't classify
    case notInstalled // command not on PATH
}

public struct DoctorResult: Sendable {
    public let status: DoctorStatus
    public let detail: String
    public init(status: DoctorStatus, detail: String) { self.status = status; self.detail = detail }
}

/// Generic, manifest-driven backend "doctor" (spec §9): a non-interactive auth/connectivity probe.
/// It NEVER hardcodes a backend — it reads the `probe` verb from `spec/backends.json` (Law 6) and
/// classifies the output with the shared `ProbeClassifier` (both are pinned by the `doctor-probe` /
/// `doctor-classify` conformance vectors). The report never carries the API key. Runs from a neutral
/// CWD so a CLI never loads the current project, bounded by a local ceiling.
public final class DoctorService: @unchecked Sendable {
    // No mutable state — `probe` uses only locals; the injected runner/resolver are themselves safe.
    private let runner: ProcessRunner
    private let pathResolver: PathResolver

    public init(runner: ProcessRunner = ProcessRunner(), pathResolver: PathResolver = PathResolver()) {
        self.runner = runner
        self.pathResolver = pathResolver
    }

    public func probe(backendId: String, ceilingMs: Int = 15_000) -> DoctorResult {
        guard let def = BackendManifest.backendDef(backendId) else {
            return DoctorResult(status: .unknown, detail: "未知后端")
        }
        let command = (def["command"] as? String) ?? backendId
        guard let exe = pathResolver.resolve(command) else {
            return DoctorResult(status: .notInstalled, detail: "未安装(命令不在 PATH)")
        }

        // No probe declared (e.g. copilot) → presence-only.
        guard let p = BackendManifest.probe(backendId) else {
            return DoctorResult(status: .ok, detail: "已安装(presence-only,无 auth 探针)")
        }
        let success = (p["successSignatures"] as? [String]) ?? []
        let fail = (p["failSignatures"] as? [String]) ?? []
        let failWins = (p["failWins"] as? Bool) ?? false
        let network = (p["network"] as? Bool) ?? false

        // kind:"log" (agy) → presence of any local credential file (no argv).
        if (p["kind"] as? String) == "log", let credFiles = p["credFiles"] as? [String] {
            let present = credFiles.contains { FileManager.default.fileExists(atPath: expand($0)) }
            return DoctorResult(status: present ? .ok : .fail,
                                detail: present ? "已登录(本地凭据文件)" : "未登录(无本地凭据文件;勾选深度检测可联网验证)")
        }

        guard let args = p["args"] as? [String], !args.isEmpty else {
            return DoctorResult(status: .ok, detail: "已安装(presence-only)")
        }

        // Bounded retry that reports the FINAL state (agy keyring race etc.). success-wins per attempt.
        let attempts = max(1, ((p["retries"] as? Int) ?? 1) + 1)
        var sawFail = false
        let cwd = NSTemporaryDirectory()  // neutral CWD — never load the current project
        for _ in 0..<attempts {
            let r = runner.run(executable: exe, args: args, stdinMode: .empty, stdinText: nil,
                               ceilingMs: ceilingMs, idleMs: 0, extraEnv: nil, workingDirectory: cwd)
            if r.notFound { return DoctorResult(status: .notInstalled, detail: "未安装(命令不在 PATH)") }
            switch ProbeClassifier.classify(r.stdout + "\n" + r.stderr, success: success, fail: fail, failWins: failWins) {
            case "ok":
                return DoctorResult(status: .ok, detail: network ? "已登录(联网验证)" : "已登录(本地凭据;未做联网验证)")
            case "fail":
                sawFail = true
            default:
                break
            }
        }
        return DoctorResult(status: sawFail ? .fail : .unknown,
                            detail: sawFail ? "未登录(本地凭据检查未通过)" : "无法判定(无明确登录/未登录信号)")
    }

    private func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}

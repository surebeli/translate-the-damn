import Foundation

/// Resolves a CLI command name to an absolute executable path on macOS.
///
/// GUI-launched apps inherit a minimal `PATH`, so the resolver falls back through
/// curated known install directories (Homebrew, nvm, npm-global, per-tool shims) and,
/// as a last resort, the login shell's `PATH`. Both the known-directory list and the
/// login-shell reader are injectable for deterministic unit tests.
public struct PathResolver {
    private let knownDirs: [String]
    private let extraPathProvider: () -> [String]
    private let pathEnvironment: String?

    /// - Parameters:
    ///   - knownDirs: Extra directories to search when `PATH` does not contain the command.
    ///     Defaults to the macOS curated list from `CLAUDE.md` / `PORTING-macos.md`.
    ///   - extraPathProvider: Closure that returns additional PATH-style directories once,
    ///     used as the final fallback. Defaults to reading `zsh -ilc 'echo $PATH'`.
    ///   - pathEnvironment: The `PATH` string to search; defaults to the process environment.
    public init(
        knownDirs: [String]? = nil,
        extraPathProvider: (() -> [String])? = nil,
        pathEnvironment: String? = nil
    ) {
        self.knownDirs = knownDirs ?? PathResolver.defaultKnownInstallPaths()
        self.extraPathProvider = extraPathProvider ?? PathResolver.defaultLoginShellPathProvider
        self.pathEnvironment = pathEnvironment
    }

    /// Returns the absolute path to an executable matching `command`, or `nil`.
    public func resolve(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Qualified paths are checked directly (no PATH walk).
        if trimmed.contains("/") {
            return executablePathIfValid(at: trimmed)
        }

        let envPathDirs = (pathEnvironment ?? ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)

        if let path = firstExecutable(in: envPathDirs, command: trimmed) { return path }
        if let path = firstExecutable(in: knownDirs, command: trimmed) { return path }
        if let path = firstExecutable(in: extraPathProvider(), command: trimmed) { return path }

        return nil
    }

    // MARK: - Search helpers

    private func firstExecutable(in directories: [String], command: String) -> String? {
        for dir in directories {
            let candidate = (dir as NSString).appendingPathComponent(command)
            if let valid = executablePathIfValid(at: candidate) {
                return valid
            }
        }
        return nil
    }

    private func executablePathIfValid(at path: String) -> String? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fm.isExecutableFile(atPath: path) else {
            return nil
        }
        return (path as NSString).standardizingPath
    }

    // MARK: - Defaults

    /// Curated install directories for macOS GUI apps that do not inherit the shell PATH.
    private static func defaultKnownInstallPaths() -> [String] {
        let staticPaths: [String] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "~/.local/bin",
            "~/.kimi-code/bin",
            "~/.grok/bin",
            "~/.npm-global/bin"
        ]

        var dirs = staticPaths.map { ($0 as NSString).expandingTildeInPath }

        if let home = ProcessInfo.processInfo.environment["HOME"] {
            let nvmBase = (home as NSString).appendingPathComponent(".nvm/versions/node")
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
                let nvmBins = versions
                    .map { ((nvmBase as NSString).appendingPathComponent($0) as NSString).appendingPathComponent("bin") }
                    .filter { FileManager.default.fileExists(atPath: $0) }
                dirs.append(contentsOf: nvmBins)
            }
        }

        return dirs
    }

    /// Reads the login shell PATH once. `zsh -ilc 'echo $PATH'` is used because zsh is the
    /// default macOS shell and `-i` sources user rc files where tools like Homebrew and nvm
    /// are configured. Output noise is ignored; the last line is taken as the PATH value.
    private static func defaultLoginShellPathProvider() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-ilc", "echo $PATH"]

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        // The login shell may print welcome text; the PATH is the final line.
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        guard let lastLine = lines.last?.trimmingCharacters(in: .whitespaces) else { return [] }

        return lastLine
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
    }
}

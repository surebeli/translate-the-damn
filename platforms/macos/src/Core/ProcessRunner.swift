import Foundation
import Darwin

public enum StdinMode {
    case none
    case empty
    case pipe
}

public struct ProcessResult {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool
    public let notFound: Bool
    public let cancelled: Bool
    public let durationMs: Int64
    public let failureDetail: String?

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool, notFound: Bool, cancelled: Bool = false, durationMs: Int64, failureDetail: String? = nil) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
        self.notFound = notFound
        self.cancelled = cancelled
        self.durationMs = durationMs
        self.failureDetail = failureDetail
    }
}

public protocol TimeSource: Sendable {
    func now() -> TimeInterval
}

public struct SystemTimeSource: TimeSource {
    public init() {}
    public func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

private final class DataBox: @unchecked Sendable {
    private var _stdout = Data()
    private var _stderr = Data()
    private let lock = NSLock()
    private var _lastOutputTime: TimeInterval

    init(initialTime: TimeInterval) {
        self._lastOutputTime = initialTime
    }

    func appendStdout(_ data: Data, time: TimeInterval) {
        lock.lock()
        _stdout.append(data)
        _lastOutputTime = time
        lock.unlock()
    }

    func appendStderr(_ data: Data, time: TimeInterval) {
        lock.lock()
        _stderr.append(data)
        _lastOutputTime = time
        lock.unlock()
    }

    func lastOutputTime() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return _lastOutputTime
    }

    func takeStdout() -> Data {
        lock.lock()
        defer { lock.unlock() }
        let d = _stdout
        _stdout = Data()
        return d
    }

    func takeStderr() -> Data {
        lock.lock()
        defer { lock.unlock() }
        let d = _stderr
        _stderr = Data()
        return d
    }
}

public final class ProcessRunner: @unchecked Sendable {
    private let timeSource: TimeSource
    private let pidLock = NSLock()
    private var currentPid: Int32?

    public init(timeSource: TimeSource = SystemTimeSource()) {
        self.timeSource = timeSource
    }

    public func cancelCurrentProcess() {
        pidLock.lock()
        let pid = currentPid
        pidLock.unlock()
        guard let pid = pid else { return }
        killTree(pid: pid)
    }

    public func run(
        executable: String,
        args: [String],
        stdinMode: StdinMode,
        stdinText: String?,
        ceilingMs: Int,
        idleMs: Int,
        extraEnv: [String: String]?,
        workingDirectory: String?,
        shouldCancel: (() -> Bool)? = nil
    ) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        if let wd = workingDirectory, FileManager.default.fileExists(atPath: wd) {
            process.currentDirectoryURL = URL(fileURLWithPath: wd)
        }

        var env = ProcessInfo.processInfo.environment
        if let extra = extraEnv {
            for (k, v) in extra { env[k] = v }
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if stdinMode == .pipe {
            let stdinPipe = Pipe()
            process.standardInput = stdinPipe
        }

        let startTime = timeSource.now()

        do {
            try process.run()
        } catch {
            let elapsed = Int64((timeSource.now() - startTime) * 1000)
            return ProcessResult(exitCode: -1, stdout: "", stderr: "", timedOut: false, notFound: true, cancelled: false, durationMs: elapsed, failureDetail: error.localizedDescription)
        }

        let outHandle = stdoutPipe.fileHandleForReading
        let errHandle = stderrPipe.fileHandleForReading
        let box = DataBox(initialTime: startTime)

        outHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                box.appendStdout(data, time: self.timeSource.now())
            }
        }
        errHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                box.appendStderr(data, time: self.timeSource.now())
            }
        }

        if stdinMode == .pipe, let stdin = (process.standardInput as? Pipe)?.fileHandleForWriting {
            let promptData = (stdinText ?? "").data(using: .utf8) ?? Data()
            stdin.write(promptData)
            stdin.closeFile()
        }

        pidLock.lock()
        currentPid = process.processIdentifier
        pidLock.unlock()
        defer {
            pidLock.lock()
            if currentPid == process.processIdentifier { currentPid = nil }
            pidLock.unlock()
        }

        var timedOut = false
        var cancelledFlag = false

        while process.isRunning {
            if let sc = shouldCancel, sc() {
                cancelledFlag = true
                break
            }
            let elapsed = (timeSource.now() - startTime) * 1000

            if ceilingMs > 0 && Int(elapsed) > ceilingMs {
                timedOut = true
                break
            }
            if idleMs > 0 && Int(elapsed) > idleMs {
                let idleElapsed = (timeSource.now() - box.lastOutputTime()) * 1000
                if Int(idleElapsed) > idleMs {
                    timedOut = true
                    break
                }
            }

            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            killTree(pid: process.processIdentifier)
            process.waitUntilExit()
        }

        outHandle.readabilityHandler = nil
        errHandle.readabilityHandler = nil

        let remainingOut = outHandle.readDataToEndOfFile()
        let remainingErr = errHandle.readDataToEndOfFile()
        if !remainingOut.isEmpty {
            box.appendStdout(remainingOut, time: timeSource.now())
        }
        if !remainingErr.isEmpty {
            box.appendStderr(remainingErr, time: timeSource.now())
        }

        let elapsed = Int64((timeSource.now() - startTime) * 1000)
        let exitCode = process.terminationStatus

        let stdoutStr = String(data: box.takeStdout(), encoding: .utf8) ?? ""
        let stderrStr = String(data: box.takeStderr(), encoding: .utf8) ?? ""

        return ProcessResult(
            exitCode: exitCode,
            stdout: AnsiStripper.strip(stdoutStr),
            stderr: AnsiStripper.strip(stderrStr),
            timedOut: timedOut,
            notFound: false,
            cancelled: cancelledFlag,
            durationMs: elapsed,
            failureDetail: timedOut ? "timeout" : (cancelledFlag ? "cancelled" : nil)
        )
    }

    private func killTree(pid: Int32) {
        let childTask = Process()
        childTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        childTask.arguments = ["-P", "\(pid)"]
        childTask.standardOutput = FileHandle.nullDevice
        childTask.standardError = FileHandle.nullDevice
        try? childTask.run()
        childTask.waitUntilExit()

        kill(pid, SIGTERM)
        usleep(500_000)
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }
}

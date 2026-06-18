import Foundation
import XCTest
@testable import TranslateTheDamnCore

final class ProcessRunnerTests: XCTestCase {
    private var runner: ProcessRunner!

    override func setUp() {
        super.setUp()
        runner = ProcessRunner()
    }

    override func tearDown() {
        runner = nil
        super.tearDown()
    }

    func testBasicExecutionEcho() {
        let result = runner.run(
            executable: "/bin/echo",
            args: ["hello", "world"],
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: 5000,
            idleMs: 0,
            extraEnv: nil,
            workingDirectory: nil
        )

        XCTAssertFalse(result.notFound)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("hello"))
        XCTAssertTrue(result.stdout.contains("world"))
    }

    func testExitCodeNonZero() {
        let result = runner.run(
            executable: "/bin/sh",
            args: ["-c", "exit 42"],
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: 5000,
            idleMs: 0,
            extraEnv: nil,
            workingDirectory: nil
        )

        XCTAssertFalse(result.notFound)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.exitCode, 42)
    }

    func testStdoutCapture() {
        let result = runner.run(
            executable: "/bin/echo",
            args: ["test_output_12345"],
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: 5000,
            idleMs: 0,
            extraEnv: nil,
            workingDirectory: nil
        )

        XCTAssertTrue(result.stdout.contains("test_output_12345"))
        XCTAssertTrue(result.stderr.isEmpty)
    }

    func testStderrCapture() {
        let result = runner.run(
            executable: "/bin/sh",
            args: ["-c", "echo stderr_test >&2"],
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: 5000,
            idleMs: 0,
            extraEnv: nil,
            workingDirectory: nil
        )

        XCTAssertTrue(result.stderr.contains("stderr_test"))
    }

    func testCeilingTimeout() {
        let result = runner.run(
            executable: "/bin/sleep",
            args: ["10"],
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: 500,
            idleMs: 0,
            extraEnv: nil,
            workingDirectory: nil
        )

        XCTAssertTrue(result.timedOut)
        XCTAssertFalse(result.notFound)
    }

    func testNotFound() {
        let result = runner.run(
            executable: "/nonexistent/path/to/binary_xyz",
            args: [],
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: 5000,
            idleMs: 0,
            extraEnv: nil,
            workingDirectory: nil
        )

        XCTAssertTrue(result.notFound)
        XCTAssertFalse(result.timedOut)
    }

    func testStdinPipe() {
        let result = runner.run(
            executable: "/bin/cat",
            args: [],
            stdinMode: .pipe,
            stdinText: "hello-stdin",
            ceilingMs: 5000,
            idleMs: 0,
            extraEnv: nil,
            workingDirectory: nil
        )

        XCTAssertEqual(result.stdout, "hello-stdin")
        XCTAssertEqual(result.exitCode, 0)
    }

    func testAnsiStripping() {
        let result = runner.run(
            executable: "/bin/sh",
            args: ["-c", "printf '\\033[32mgreen\\033[0m text'"],
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: 5000,
            idleMs: 0,
            extraEnv: nil,
            workingDirectory: nil
        )

        XCTAssertEqual(result.stdout, "green text")
    }

    func testCarriageReturnStripping() {
        let result = runner.run(
            executable: "/bin/sh",
            args: ["-c", "printf 'line1\\r\\nline2'"],
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: 5000,
            idleMs: 0,
            extraEnv: nil,
            workingDirectory: nil
        )

        XCTAssertFalse(result.stdout.contains("\r"))
        XCTAssertTrue(result.stdout.contains("line1"))
        XCTAssertTrue(result.stdout.contains("line2"))
    }

    func testDurationMsIsPositive() {
        let result = runner.run(
            executable: "/bin/echo",
            args: ["test"],
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: 5000,
            idleMs: 0,
            extraEnv: nil,
            workingDirectory: nil
        )

        XCTAssertGreaterThan(result.durationMs, 0)
    }

    func testExtraEnv() {
        let result = runner.run(
            executable: "/bin/sh",
            args: ["-c", "echo $TEST_VAR_123"],
            stdinMode: .empty,
            stdinText: nil,
            ceilingMs: 5000,
            idleMs: 0,
            extraEnv: ["TEST_VAR_123": "my-env-value"],
            workingDirectory: nil
        )

        XCTAssertTrue(result.stdout.contains("my-env-value"))
    }
}

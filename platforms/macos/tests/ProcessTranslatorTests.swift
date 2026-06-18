import Foundation
import XCTest
@testable import TranslateTheDamnCore

final class ProcessTranslatorTests: XCTestCase {

    func testSuccessPathWithEchoAsCommand() {
        let config = BackendConfig(
            type: "cli",
            command: "/bin/echo",
            model: "test-model"
        )
        let translator = ProcessTranslator(id: "claude", config: config)
        let result = translator.translate(text: "Hello world", model: "gpt-4")

        XCTAssertTrue(result.ok, "Expected success but got: \(result.text)")
        XCTAssertTrue(result.text.contains("--model"), "Expected output to contain args")
        XCTAssertFalse(result.text.isEmpty)
    }

    func testNotFoundStatusForNonExistentCommand() {
        let config = BackendConfig(
            type: "cli",
            command: "nonexistent-command-xyz-123"
        )
        let pathResolver = PathResolver(
            knownDirs: [],
            extraPathProvider: { [] },
            pathEnvironment: ""
        )
        let translator = ProcessTranslator(id: "claude", config: config, pathResolver: pathResolver)
        let result = translator.translate(text: "test", model: "gpt-4")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, .notFound)
    }

    func testNotFoundStatusForUnknownBackend() {
        let pathResolver = PathResolver(
            knownDirs: [],
            extraPathProvider: { [] },
            pathEnvironment: ""
        )
        let config = BackendConfig(
            type: "cli",
            command: "truly-nonexistent-command-abc-123"
        )
        let translator = ProcessTranslator(id: "nonexistent-backend-xyz", config: config, pathResolver: pathResolver)
        let result = translator.translate(text: "test", model: "gpt-4")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, .notFound)
    }

    func testSuccessWithPromptViaArg() {
        let config = BackendConfig(
            type: "cli",
            command: "/bin/echo",
            model: "test-model"
        )
        let translator = ProcessTranslator(id: "copilot", config: config)
        let result = translator.translate(text: "translate_this", model: "gpt-4")

        XCTAssertTrue(result.ok, "Expected success but got: \(result.text)")
        XCTAssertFalse(result.text.isEmpty)
    }

    func testSuccessWithPromptViaStdinDash() {
        let config = BackendConfig(
            type: "cli",
            command: "/bin/cat",
            model: "test-model"
        )
        let translator = ProcessTranslator(id: "codex", config: config)
        let result = translator.translate(text: "stdin-text", model: "gpt-4")

        XCTAssertTrue(result.ok, "Expected success but got: \(result.text)")
    }

    func testTimeoutStatusForSlowProcess() {
        let runner = ProcessRunner()
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
        XCTAssertTrue(result.timedOut, "Process should timeout with low ceiling")
    }

    func testJsonResultPathParsing() {
        let raw = "{\"result\": \"translated text here\"}"
        let jsonPath = "result"

        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = BackendManifest.eval(root: obj, path: jsonPath) {
            XCTAssertEqual(value, "translated text here")
        } else {
            XCTFail("Should parse JSON path")
        }
    }

    func testResponsePathEvalForGoogleV2Response() {
        let response: [String: Any] = [
            "data": [
                "translations": [
                    ["translatedText": "Hola mundo"]
                ]
            ]
        ]
        let path = "data.translations[0].translatedText"
        let result = BackendManifest.eval(root: response, path: path)
        XCTAssertEqual(result, "Hola mundo")
    }

    func testResponsePathEvalForDoubaoResponse() {
        let response: [String: Any] = [
            "output": [
                [
                    "type": "message",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Bonjour le monde"
                        ]
                    ]
                ]
            ]
        ]
        let path = "output[type=message].content[type=output_text].text"
        let result = BackendManifest.eval(root: response, path: path)
        XCTAssertEqual(result, "Bonjour le monde")
    }

    func testTranslateStatusEnumValues() {
        XCTAssertEqual(TranslateStatus.success.rawValue, "success")
        XCTAssertEqual(TranslateStatus.authFail.rawValue, "authFail")
        XCTAssertEqual(TranslateStatus.timeout.rawValue, "timeout")
        XCTAssertEqual(TranslateStatus.notFound.rawValue, "notFound")
        XCTAssertEqual(TranslateStatus.badOutput.rawValue, "badOutput")
        XCTAssertEqual(TranslateStatus.unknownFail.rawValue, "unknownFail")
    }

    func testTranslationResultFailedFactory() {
        let result = TranslationResult.failed(.authFail, "Invalid key")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, .authFail)
        XCTAssertEqual(result.text, "Invalid key")
        XCTAssertEqual(result.detail, "Invalid key")
    }

    func testTranslationResultSuccessAndFailureFactories() {
        let success = TranslationResult.successful("text")
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.text, "text")
        XCTAssertEqual(success.status, .success)

        let failure = TranslationResult.failure("error")
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.status, .unknownFail)
    }

    func testTimeoutStatus() {
        let runner = ProcessRunner()
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
    }
}

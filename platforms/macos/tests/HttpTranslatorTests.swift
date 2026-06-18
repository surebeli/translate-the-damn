import Foundation
import XCTest
@testable import TranslateTheDamnCore

final class HttpTranslatorTests: XCTestCase {

    func testAuthFailWhenNoApiKey() {
        let config = BackendConfig(
            type: "http",
            apiKey: nil
        )
        let translator = HttpTranslator(id: "google-v2", config: config)
        let result = translator.translate(text: "hello", model: "")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, .authFail)
    }

    func testAuthFailWhenEmptyApiKey() {
        let config = BackendConfig(
            type: "http",
            apiKey: ""
        )
        let translator = HttpTranslator(id: "google-v2", config: config)
        let result = translator.translate(text: "hello", model: "")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, .authFail)
    }

    func testAuthFailWhenWhitespaceApiKey() {
        let config = BackendConfig(
            type: "http",
            apiKey: "   "
        )
        let translator = HttpTranslator(id: "google-v2", config: config)
        let result = translator.translate(text: "hello", model: "")

        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, .authFail)
    }

    func testResponsePathEvalGoogleV2Shape() {
        let response: [String: Any] = [
            "data": [
                "translations": [
                    ["translatedText": "你好世界"]
                ]
            ]
        ]
        let result = BackendManifest.eval(root: response, path: "data.translations[0].translatedText")
        XCTAssertEqual(result, "你好世界")
    }

    func testResponsePathEvalDoubaoShape() {
        let response: [String: Any] = [
            "output": [
                [
                    "type": "message",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "你好世界"
                        ]
                    ]
                ]
            ]
        ]
        let result = BackendManifest.eval(root: response, path: "output[type=message].content[type=output_text].text")
        XCTAssertEqual(result, "你好世界")
    }

    func testResponsePathEvalMissingPathReturnsNil() {
        let response: [String: Any] = [
            "data": [
                "translations": []
            ]
        ]
        let result = BackendManifest.eval(root: response, path: "data.translations[0].translatedText")
        XCTAssertNil(result)
    }

    func testResponsePathEvalNestedJson() {
        let response: [String: Any] = [
            "choices": [
                [
                    "message": [
                        "content": "translated content"
                    ]
                ]
            ]
        ]
        let result = BackendManifest.eval(root: response, path: "choices[0].message.content")
        XCTAssertEqual(result, "translated content")
    }

    func testTranslationResultFailedAuthFail() {
        let result = TranslationResult.failed(.authFail, "auth error")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, .authFail)
    }

    func testTranslationResultFailedBadOutput() {
        let result = TranslationResult.failed(.badOutput, "no translation")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, .badOutput)
    }

    func testTranslationResultFailedTimeout() {
        let result = TranslationResult.failed(.timeout, "timeout")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, .timeout)
    }

    func testTranslationResultFailedUnknownFail() {
        let result = TranslationResult.failed(.unknownFail, "generic error")
        XCTAssertFalse(result.ok)
        XCTAssertEqual(result.status, .unknownFail)
    }
}

import XCTest
@testable import TranslateTheDamnCore

final class BackendManifestTests: XCTestCase {

    func testEvalSimplePath() {
        let json: [String: Any] = [
            "data": [
                "translations": [
                    ["translatedText": "你好"]
                ]
            ]
        ]
        let result = BackendManifest.eval(root: json, path: "data.translations[0].translatedText")
        XCTAssertEqual(result, "你好")
    }

    func testEvalArrayFilter() {
        let json: [String: Any] = [
            "output": [
                ["type": "other", "content": []],
                [
                    "type": "message",
                    "content": [
                        ["type": "input_text", "text": "ignored"],
                        ["type": "output_text", "text": "你好世界"]
                    ]
                ]
            ]
        ]
        let result = BackendManifest.eval(
            root: json,
            path: "output[type=message].content[type=output_text].text"
        )
        XCTAssertEqual(result, "你好世界")
    }

    func testEvalMissingKeyReturnsNil() {
        let json: [String: Any] = ["a": ["b": "c"]]
        let result = BackendManifest.eval(root: json, path: "a.x")
        XCTAssertNil(result)
    }

    func testEvalIndexOutOfBoundsReturnsNil() {
        let json: [String: Any] = ["arr": ["one"]]
        let result = BackendManifest.eval(root: json, path: "arr[1]")
        XCTAssertNil(result)
    }

    func testEvalNonStringFinalValueReturnsNil() {
        let json: [String: Any] = ["count": 42]
        let result = BackendManifest.eval(root: json, path: "count")
        XCTAssertNil(result)
    }

    func testEvalNonArrayBracketReturnsNil() {
        let json: [String: Any] = ["obj": ["key": "value"]]
        let result = BackendManifest.eval(root: json, path: "obj[0]")
        XCTAssertNil(result)
    }

    func testEvalFilterKeyNotFoundReturnsNil() {
        let json: [String: Any] = [
            "output": [
                ["type": "message", "content": ["text": "hello"]]
            ]
        ]
        let result = BackendManifest.eval(root: json, path: "output[type=unknown].content.text")
        XCTAssertNil(result)
    }

    func testEvalMissingClosingBracketReturnsNil() {
        let json: [String: Any] = ["arr": ["a", "b"]]
        let result = BackendManifest.eval(root: json, path: "arr[0")
        XCTAssertNil(result)
    }

    func testBuildBodyOmitsEmptyKeys() {
        let template: [String: Any] = [
            "q": "{text}",
            "target": "{target}",
            "source": "{source}"
        ]
        let vars: [String: String] = ["text": "Hi", "target": "zh", "source": ""]
        let omit = Set(["source"])
        let body = BackendManifest.buildBody(template: template, vars: vars, omitWhenEmpty: omit)
        XCTAssertTrue(body.contains("\"q\":\"Hi\""))
        XCTAssertTrue(body.contains("\"target\":\"zh\""))
        XCTAssertFalse(body.contains("\"source\""))
    }

    func testBuildBodyPreservesNonEmptyKeys() {
        let template: [String: Any] = [
            "q": "{text}",
            "source": "{source}"
        ]
        let vars: [String: String] = ["text": "Hi", "source": "en"]
        let omit = Set(["source"])
        let body = BackendManifest.buildBody(template: template, vars: vars, omitWhenEmpty: omit)
        XCTAssertTrue(body.contains("\"source\":\"en\""))
    }
}

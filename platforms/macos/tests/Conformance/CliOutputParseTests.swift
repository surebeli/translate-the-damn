import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `cli-output-parse.json`: `BackendManifest.collectJsonl` extracts the translation
/// from stream-json / NDJSON CLI stdout (opencode/mimo `type==text -> part.text`; kimi
/// `role==assistant -> content`; meta/chrome lines ignored; no-match -> ""). Pins the contract that
/// was previously unvectored (the macOS jsonl gap + the wrong kimi spec both slipped through).
final class CliOutputParseTests: XCTestCase {
    func testCliOutputParse() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("cli-output-parse.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])
        for c in cases {
            let name = (c["name"] as? String) ?? "?"
            let input = try XCTUnwrap(c["in"] as? [String: Any], "[\(name)] missing in")
            let raw = try XCTUnwrap(input["raw"] as? String, "[\(name)] missing raw")
            let typeField = (input["jsonlTypePath"] as? String) ?? "type"   // default discriminator
            let typeValue = try XCTUnwrap(input["jsonlType"] as? String, "[\(name)] missing jsonlType")
            let textPath = try XCTUnwrap(input["jsonlTextPath"] as? String, "[\(name)] missing jsonlTextPath")
            let expected = try XCTUnwrap(c["out"] as? String, "[\(name)] out not a string")
            XCTAssertEqual(BackendManifest.collectJsonl(raw, typeField: typeField, typeValue: typeValue, textPath: textPath),
                           expected, "cli-output-parse [\(name)]")
        }
    }
}

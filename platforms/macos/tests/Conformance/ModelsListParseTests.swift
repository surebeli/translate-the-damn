import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `models-list-parse.json`: `ModelEnumerator.parseModelsList` extracts `provider/name`
/// model ids from a CLI `modelsCmd` stdout (mimo/opencode `models`), dropping chrome/blank/spaced lines,
/// ANSI-stripping, deduping in order. Pins the parser that lets CLI backends enumerate live models —
/// macOS previously had NO CLI enumeration path (parity gap vs Windows).
final class ModelsListParseTests: XCTestCase {
    func testModelsListParse() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("models-list-parse.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])
        for c in cases {
            let name = (c["name"] as? String) ?? "?"
            let input = try XCTUnwrap(c["in"] as? [String: Any], "[\(name)] missing in")
            let raw = try XCTUnwrap(input["stdout"] as? String, "[\(name)] missing stdout")
            let stdout = raw.replacingOccurrences(of: "<ESC>", with: "\u{1B}").replacingOccurrences(of: "<CR>", with: "\r")
            let expected = (try XCTUnwrap(c["out"] as? [Any], "[\(name)] out")).compactMap { $0 as? String }
            XCTAssertEqual(ModelEnumerator.parseModelsList(stdout), expected, "models-list-parse [\(name)]")
        }
    }
}

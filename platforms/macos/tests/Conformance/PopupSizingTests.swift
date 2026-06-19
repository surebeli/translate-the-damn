import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `popup-sizing.json`: scalar out — `PopupSizing.sizeClass(sourceChars:)` returns
/// "normal" or "large" ("large" when the source length is > 500 chars). Spec §8.
final class PopupSizingTests: XCTestCase {
    func testPopupSizing() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("popup-sizing.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])
        for c in cases {
            let name = (c["name"] as? String) ?? "?"
            let input = try XCTUnwrap(c["in"] as? [String: Any], "[\(name)] missing in")
            let expected = try XCTUnwrap(c["out"] as? String, "[\(name)] out not a string")
            let sourceChars = try XCTUnwrap(input["sourceChars"] as? Int, "[\(name)] missing sourceChars")
            XCTAssertEqual(PopupSizing.sizeClass(sourceChars: sourceChars), expected,
                           "popup-sizing [\(name)]")
        }
    }
}

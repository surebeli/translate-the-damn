import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `doctor-classify.json`: `ProbeClassifier.classify` must normalize (lowercase +
/// strip all whitespace) and match success/fail signatures with the success-wins / failWins rules.
final class DoctorClassifyTests: XCTestCase {
    func testDoctorClassify() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("doctor-classify.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])
        for c in cases {
            let name = (c["name"] as? String) ?? "?"
            let text = try XCTUnwrap(c["text"] as? String, "[\(name)] missing text")
            let success = (c["success"] as? [String]) ?? []
            let fail = (c["fail"] as? [String]) ?? []
            let failWins = (c["failWins"] as? Bool) ?? false
            let expected = try XCTUnwrap(c["out"] as? String, "[\(name)] missing out")
            XCTAssertEqual(ProbeClassifier.classify(text, success: success, fail: fail, failWins: failWins),
                           expected, "doctor-classify [\(name)]")
        }
    }
}

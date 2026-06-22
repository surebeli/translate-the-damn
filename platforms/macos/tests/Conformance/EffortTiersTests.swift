import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `effort-tiers.json`: `BackendManifest.effortTiers(_:)` must return, for each
/// backend, the exact tier list declared in `spec/backends.json` (absent key → `[]`). This is the
/// per-vendor effort selector's data source; both platforms read the same shared manifest (Law 2/6).
final class EffortTiersTests: XCTestCase {
    func testEffortTiers() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("effort-tiers.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])
        for c in cases {
            let backend = try XCTUnwrap(c["backend"] as? String, "case missing backend")
            let expected = try XCTUnwrap(c["tiers"] as? [String], "[\(backend)] tiers not a string array")
            XCTAssertEqual(BackendManifest.effortTiers(backend), expected, "effort-tiers [\(backend)]")
        }
    }
}

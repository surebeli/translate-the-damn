import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `config-defaults.json`: serialize `ConfigService.defaultConfig()` to JSON
/// (camelCase, nulls omitted), then apply each `assert[]` entry. Ops: `equals` / `count` /
/// `contains` (string substring) / `containsItem` (array membership). Path is dot-separated.
final class ConfigDefaultsTests: XCTestCase {
    func testConfigDefaults() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("config-defaults.json", dir, self))
        let asserts = try XCTUnwrap(vec["assert"] as? [[String: Any]])

        // Serialize the default config (camelCase, nulls omitted) and parse back to [String: Any]
        // for path navigation — mirrors the Windows runner serializing then walking the JsonDocument.
        let cfg = ConfigService.defaultConfig()
        let data = try JSONEncoder().encode(cfg)
        let serialized = try JSONSerialization.jsonObject(with: data)

        for a in asserts {
            guard let path = a["path"] as? String else {
                XCTFail("config assert missing 'path' field")
                continue
            }
            // Soft pattern: a missing path must XCTFail but NOT halt the loop, so every assert
            // is evaluated (the M1 stub returns empty `backends`, so all `backends.*` paths are
            // missing — they must each surface individually, not stop at the first).
            guard let el = ConformanceHarness.navigate(serialized, path) else {
                XCTFail("config [\(path)] path missing in serialized default config")
                continue
            }

            if let eq = a["equals"] {
                assertEquals(el, eq, path: path)
            } else if let cnt = a["count"] as? Int {
                let actual = ConformanceHarness.countOf(el)
                XCTAssertEqual(actual, cnt, "config [\(path)] count")
            } else if let contains = a["contains"] as? String {
                let s = (el as? String) ?? ""
                XCTAssertTrue(s.contains(contains), "config [\(path)] contains '\(contains)'")
            } else if let item = a["containsItem"] as? String {
                XCTAssertTrue(ConformanceHarness.arrayContains(el, item),
                              "config [\(path)] containsItem '\(item)'")
            } else {
                XCTFail("config [\(path)] unknown op")
            }
        }
    }

    /// `equals` across scalar kinds (bool/int/string), matching the Windows `JsonEquals`.
    ///
    /// CRITICAL: kind discrimination must NOT rely on `expected as? Bool` — `JSONSerialization`
    /// returns JSON numbers as `NSNumber`, and Swift coerces an integer `NSNumber` (e.g. `1`) to
    /// `Bool` (`Optional(true)`). So `expected as? Bool` succeeds for JSON `1`, conflationg integer
    /// and boolean. A wrong non-zero integer (e.g. `version == 2`) would then compare as Bool
    /// (`2→true == 1→true`) and FALSE-PASS — breaking the parity gate (Constitution Law 2).
    ///
    /// The reliable discriminator is `CFGetTypeID(expected as CFTypeRef) == CFBooleanGetTypeID()`,
    /// which is true only for genuine JSON booleans. Numbers compare by numeric value (Double with a
    /// tiny tolerance), so equal Int-vs-Double boxings are equal.
    private func assertEquals(_ actual: Any, _ expected: Any, path: String) {
        if ConformanceHarness.isJSONBoolean(expected) {
            let b = expected as! Bool
            XCTAssertEqual(actual as? Bool, b, "config [\(path)] equals \(b)")
        } else if let s = expected as? String {
            XCTAssertEqual(actual as? String, s, "config [\(path)] equals \"\(s)\"")
        } else if let expNum = expected as? NSNumber {
            // Number compare by value (tolerant of Int-vs-Double boxing). Config `equals` numbers
            // are integers (1, 6) but be robust to Double.
            guard let actNum = actual as? NSNumber else {
                XCTAssertEqual(actual as? NSNumber, expNum, "config [\(path)] equals \(expNum)")
                return
            }
            let exp = expNum.doubleValue
            let act = actNum.doubleValue
            let equal = abs(exp - act) <= max(abs(exp), abs(act), 1.0) * 1e-9
            XCTAssertTrue(equal, "config [\(path)] equals \(expNum) — got \(actNum)")
        } else {
            XCTFail("config [\(path)] equals unsupported expected kind")
        }
    }
}

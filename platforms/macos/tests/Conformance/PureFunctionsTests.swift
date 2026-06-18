import XCTest
@testable import TranslateTheDamnCore

/// Conformance for the three pure-function vectors: `prompt-builder`, `ansi-stripper`,
/// `hotkey-parser`. Each `case` has `in` + `out`; scalar `out` ⇒ exact equality; object `out`
/// (hotkey) ⇒ assert each present field (subset; extra native fields ignored). `virtualKey` is the
/// Win32 VK code.
final class PureFunctionsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                            "could not locate repo-root conformance/ from #file")
    }

    // MARK: prompt-builder.json — scalar out, exact equality
    func testPromptBuilder() throws {
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("prompt-builder.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])
        for c in cases {
            let name = (c["name"] as? String) ?? "?"
            let input = try XCTUnwrap(c["in"] as? [String: Any], "[\(name)] missing in")
            let expected = try XCTUnwrap(c["out"] as? String, "[\(name)] out not a string")
            let template = try XCTUnwrap(input["template"] as? String)
            let content = try XCTUnwrap(input["content"] as? String)
            let actual = PromptBuilder.build(template: template, content: content)
            XCTAssertEqual(actual, expected, "prompt-builder [\(name)]")
        }
    }

    // MARK: ansi-stripper.json — markers substituted, scalar out, exact equality
    func testAnsiStripper() throws {
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("ansi-stripper.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])
        for c in cases {
            let name = (c["name"] as? String) ?? "?"
            let input = try XCTUnwrap(c["in"] as? [String: Any], "[\(name)] missing in")
            let expected = try XCTUnwrap(c["out"] as? String, "[\(name)] out not a string")
            let raw = try XCTUnwrap(input["s"] as? String)
            let actual = AnsiStripper.strip(ConformanceHarness.substituteMarkers(raw))
            XCTAssertEqual(actual, expected, "ansi-stripper [\(name)]")
        }
    }

    // MARK: hotkey-parser.json — object out, subset assertions
    func testHotkeyParser() throws {
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("hotkey-parser.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])
        for c in cases {
            let name = (c["name"] as? String) ?? "?"
            let input = try XCTUnwrap(c["in"] as? [String: Any], "[\(name)] missing in")
            let out = try XCTUnwrap(c["out"] as? [String: Any], "[\(name)] out not an object")
            let text = try XCTUnwrap(input["text"] as? String)
            let r = HotkeyParser.parse(text)

            if let v = out["isValid"] as? Bool {
                XCTAssertEqual(r.isValid, v, "hotkey [\(name)] isValid")
            }
            if let v = out["hasControl"] as? Bool {
                XCTAssertEqual(r.hasControl, v, "hotkey [\(name)] hasControl")
            }
            if let v = out["hasAlt"] as? Bool {
                XCTAssertEqual(r.hasAlt, v, "hotkey [\(name)] hasAlt")
            }
            if let v = out["hasWin"] as? Bool {
                XCTAssertEqual(r.hasWin, v, "hotkey [\(name)] hasWin")
            }
            if let v = out["hasShift"] as? Bool {
                XCTAssertEqual(r.hasShift, v, "hotkey [\(name)] hasShift")
            }
            if let v = out["virtualKey"] as? Int {
                XCTAssertEqual(r.virtualKey, v, "hotkey [\(name)] virtualKey (Win32 VK)")
            }
            if let v = out["display"] as? String {
                XCTAssertEqual(r.display, v, "hotkey [\(name)] display")
            }
        }
    }
}

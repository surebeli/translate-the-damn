import Foundation
import XCTest

/// Shared harness for the macOS conformance runner: locates the repo-root `conformance/` dir by
/// walking up from this file (mirrors the Windows harness's `FindUp`), loads vector JSON via
/// `JSONSerialization` (flexible `Any`/`[[String:Any]]` access), and provides assertion helpers that
/// map to the per-format semantics in `conformance/README.md`.
///
/// The runner itself is the parity gate (Constitution Law 2) and must be CORRECT even while the core
/// stubs are RED. It feeds each vector case through the native Swift impl and asserts via XCTest, so
/// `swift test` exits non-zero on any mismatch.
enum ConformanceHarness {
    /// Walk up from `#file` until a `conformance/` sibling directory is found.
    static func locateConformanceDir() -> URL? {
        var url = URL(fileURLWithPath: #file).deletingLastPathComponent()
        while url.path != "/" {
            let candidate = url.appendingPathComponent("conformance", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    /// Load a vector file as an `[String: Any]` root. Fails the test if the file is missing/invalid.
    static func loadVector(_ file: String, _ dir: URL, _ testCase: XCTestCase) -> [String: Any]? {
        let path = dir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: path) else {
            XCTFail("conformance file missing: \(file)")
            return nil
        }
        do {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                XCTFail("conformance file not a JSON object: \(file)")
                return nil
            }
            return obj
        } catch {
            XCTFail("conformance file invalid JSON: \(file) — \(error)")
            return nil
        }
    }

    /// Replace the printable marker tokens used in `ansi-stripper` inputs with the real bytes, BEFORE
    /// feeding the impl. `<ESC>` → 0x1B, `<CR>` → 0x0D (per vector docstring).
    static func substituteMarkers(_ s: String) -> String {
        s.replacingOccurrences(of: "<ESC>", with: "\u{1B}")
         .replacingOccurrences(of: "<CR>", with: "\r")
    }

    // MARK: - path navigation (config-defaults)

    /// Navigate a serialized JSON object (`[String: Any]`) by a dot-separated path.
    static func navigate(_ root: Any, _ path: String) -> Any? {
        var current: Any = root
        for seg in path.split(separator: ".", omittingEmptySubsequences: false) {
            guard let obj = current as? [String: Any], let next = obj[String(seg)] else { return nil }
            current = next
        }
        return current
    }

    /// Count of an array or object (mirrors the Windows `CountOf`).
    static func countOf(_ el: Any) -> Int? {
        if let arr = el as? [Any] { return arr.count }
        if let obj = el as? [String: Any] { return obj.count }
        return nil
    }

    /// Array membership (string item).
    static func arrayContains(_ el: Any, _ item: String) -> Bool {
        guard let arr = el as? [Any] else { return false }
        return arr.contains { ($0 as? String) == item }
    }

    /// Reliable JSON-boolean discriminator.
    ///
    /// `JSONSerialization` surfaces JSON booleans AND JSON numbers as `NSNumber`. Swift's `as? Bool`
    /// coerces an integer `NSNumber` (e.g. `1`) to `Bool` (`Optional(true)`), so `expected as? Bool`
    /// cannot tell JSON `1` from JSON `true`. `CFGetTypeID(...) == CFBooleanGetTypeID()` is true only
    /// for genuine `__NSCFBoolean` (JSON booleans), false for `__NSCFNumber` (JSON numbers), and is
    /// the only correct discriminator. Used by `ConfigDefaultsTests.assertEquals` to keep integer
    /// and boolean `equals` asserts from conflating (a wrong non-zero int must NOT false-pass).
    static func isJSONBoolean(_ value: Any) -> Bool {
        CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID()
    }
}

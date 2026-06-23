import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `i18n-locale-resolve.json`: `LocaleResolver.resolve(configUiLang:systemLocale:)`
/// must, for each case, return the exact `expected` UI locale from the frozen table (spec §3).
/// This is the data source for the in-app "Display language" selector + system-following default;
/// both platforms read the same shared vector so resolution never drifts (Law 2/6).
final class LocaleResolveTests: XCTestCase {
    func testLocaleResolve() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("i18n-locale-resolve.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])
        for c in cases {
            let configUiLang = try XCTUnwrap(c["configUiLang"] as? String, "case missing configUiLang")
            let systemLocale = try XCTUnwrap(c["systemLocale"] as? String, "case missing systemLocale")
            let expected = try XCTUnwrap(c["expected"] as? String, "case missing expected")
            let actual = LocaleResolver.resolve(configUiLang: configUiLang, systemLocale: systemLocale)
            XCTAssertEqual(actual, expected,
                           "locale-resolve (configUiLang=\"\(configUiLang)\", systemLocale=\"\(systemLocale)\")")
        }
    }
}

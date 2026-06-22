import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `credential-discovery.json`: the static-key/OAuth import boundary. Each case feeds
/// `CredentialClassifier.classify` and asserts import-or-SKIP + provider/protocol/suggestedId. Pins the
/// security contract (never import OAuth tokens / subscription hosts) identically on every platform.
final class CredentialDiscoveryTests: XCTestCase {
    func testCredentialDiscovery() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("credential-discovery.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])

        for c in cases {
            let name = (c["name"] as? String) ?? "?"
            let baseUrl = c["baseUrl"] as? String
            let key = c["key"] as? String
            let expect = try XCTUnwrap(c["expect"] as? [String: Any], "[\(name)] missing expect")
            let wantImport = (expect["import"] as? Bool) ?? false

            let got = CredentialClassifier.classify(source: "test", baseUrl: baseUrl, key: key)
            XCTAssertEqual(got != nil, wantImport, "cred-classify [\(name)] import?")

            if wantImport, let got = got {
                if let p = expect["provider"] as? String { XCTAssertEqual(got.provider, p, "cred-classify [\(name)] provider") }
                if let pr = expect["protocol"] as? String { XCTAssertEqual(got.protocolName, pr, "cred-classify [\(name)] protocol") }
                if let si = expect["suggestedId"] as? String { XCTAssertEqual(got.suggestedId, si, "cred-classify [\(name)] suggestedId") }
            }
        }
    }
}

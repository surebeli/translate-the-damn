import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `backend-requests.json`: each case has `backend` + `config` + `text` + `expect`.
/// Build the call via `HttpBackend.buildCall`, then assert method / urlContains / urlNotContains /
/// headers / bodyContains / bodyNotContains. This pins the request shape every platform must produce
/// (spec §6.1 google-v2, §6.2 doubao).
final class BackendRequestsTests: XCTestCase {
    func testBackendRequests() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("backend-requests.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])

        for c in cases {
            let name = (c["name"] as? String) ?? "?"
            let backend = try XCTUnwrap(c["backend"] as? String, "[\(name)] missing backend")
            let text = try XCTUnwrap(c["text"] as? String, "[\(name)] missing text")
            let configDict = try XCTUnwrap(c["config"] as? [String: Any], "[\(name)] missing config")
            let expect = try XCTUnwrap(c["expect"] as? [String: Any], "[\(name)] missing expect")

            // Decode the per-case config slice into the typed BackendTestConfig.
            let configData = try JSONSerialization.data(withJSONObject: configDict)
            let config = try JSONDecoder().decode(BackendTestConfig.self, from: configData)
            let promptTemplate = (c["promptTemplate"] as? String) ?? ""

            let call = HttpBackend.buildCall(backend: backend, config: config, text: text, promptTemplate: promptTemplate)

            if let m = expect["method"] as? String {
                XCTAssertEqual(call.method, m, "backend-req [\(name)] method")
            }
            if let urlContains = expect["urlContains"] as? [String] {
                for s in urlContains {
                    XCTAssertTrue(call.url.contains(s), "backend-req [\(name)] url ∋ '\(s)'")
                }
            }
            if let urlNotContains = expect["urlNotContains"] as? [String] {
                for s in urlNotContains {
                    XCTAssertFalse(call.url.contains(s), "backend-req [\(name)] url ∌ '\(s)'")
                }
            }
            if let headers = expect["headers"] as? [String: String] {
                for (k, v) in headers {
                    XCTAssertEqual(call.headers[k], v, "backend-req [\(name)] header \(k)")
                }
            }
            if let bodyContains = expect["bodyContains"] as? [String] {
                for s in bodyContains {
                    XCTAssertTrue(call.body.contains(s), "backend-req [\(name)] body ∋ \(s)")
                }
            }
            if let bodyNotContains = expect["bodyNotContains"] as? [String] {
                for s in bodyNotContains {
                    XCTAssertFalse(call.body.contains(s), "backend-req [\(name)] body ∌ \(s)")
                }
            }
        }
    }
}

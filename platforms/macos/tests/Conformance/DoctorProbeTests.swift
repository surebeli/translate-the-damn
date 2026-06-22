import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `doctor-probe.json`: `BackendManifest.probe(_:)` must expose each backend's probe
/// declaration from the shared `spec/backends.json` (args | kind, network, retries, signatures,
/// failWins). A backend with no probe (copilot) → nil, so `args` reads as null. Only the fields a
/// case declares are asserted (soft), mirroring how config-defaults checks declared paths.
final class DoctorProbeTests: XCTestCase {
    func testDoctorProbe() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("doctor-probe.json", dir, self))
        let cases = try XCTUnwrap(vec["cases"] as? [[String: Any]])
        for c in cases {
            let backend = try XCTUnwrap(c["backend"] as? String, "case missing backend")
            let probe = BackendManifest.probe(backend)

            if c.keys.contains("args") {
                let actual = probe?["args"] as? [String]
                if c["args"] is NSNull || c["args"] == nil {
                    XCTAssertNil(actual, "probe [\(backend)] args should be null (presence-only)")
                } else {
                    XCTAssertEqual(actual, c["args"] as? [String], "probe [\(backend)] args")
                }
            }
            if let kind = c["kind"] as? String {
                XCTAssertEqual(probe?["kind"] as? String, kind, "probe [\(backend)] kind")
            }
            if let net = c["network"] as? Bool {
                XCTAssertEqual(probe?["network"] as? Bool ?? false, net, "probe [\(backend)] network")
            }
            if let retries = c["retries"] as? Int {
                XCTAssertEqual(probe?["retries"] as? Int, retries, "probe [\(backend)] retries")
            }
            if let failWins = c["failWins"] as? Bool {
                XCTAssertEqual(probe?["failWins"] as? Bool ?? false, failWins, "probe [\(backend)] failWins")
            }
            if let ss = c["successSignatures"] as? [String] {
                XCTAssertEqual(probe?["successSignatures"] as? [String], ss, "probe [\(backend)] successSignatures")
            }
            if let fs = c["failSignatures"] as? [String] {
                XCTAssertEqual(probe?["failSignatures"] as? [String], fs, "probe [\(backend)] failSignatures")
            }
        }
    }
}

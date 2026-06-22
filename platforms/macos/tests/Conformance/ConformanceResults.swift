import Foundation
import XCTest

/// Emits per-vector pass/fail for the macOS conformance runner so `scripts/parity-verify.py` can
/// cross-check PARITY.md's macOS column against REALITY (mechanism #9 — the 72cea10-class guard:
/// a vector green on a platform while PARITY still says 🚧).
///
/// How it stays drift-free: the vector *name* is recorded by `ConformanceHarness.loadVector(...)`
/// itself — the same string literal that names the JSON file — so there is no hand-maintained
/// test→vector map to fall out of sync. Each conformance test method loads exactly one vector, so we
/// key the binding on the running test's `name`. An `XCTestObservation` then marks the vector green
/// iff that test recorded no failures.
///
/// Inert by default. Only writes when `TTD_EMIT_RESULTS` is set to an output path (CI sets it). So
/// normal `swift test` runs are unaffected.
final class ConformanceResults: NSObject, XCTestObservation {
    // Swift 6: the singleton holds mutable state mutated from XCTest callbacks. We don't pin it to an
    // actor (the XCTestObservation requirements are nonisolated), so guard all state with a lock and
    // mark the static `nonisolated(unsafe)` — access is serialized below, which is the safety the
    // compiler can't prove on its own.
    nonisolated(unsafe) static let shared = ConformanceResults()

    private let lock = NSLock()
    private var registered = false
    private var vectorForTest: [String: String] = [:]   // testCase.name → vector stem
    private var failedTests: Set<String> = []           // testCase.name with ≥1 recorded failure
    private var results: [String: Bool] = [:]           // vector stem → green

    /// Called from `loadVector`. Binds the running test to the vector it just loaded and ensures the
    /// observer is attached (idempotent). Safe no-op if emission isn't requested.
    func willRun(vector stem: String, testCase: XCTestCase) {
        guard ProcessInfo.processInfo.environment["TTD_EMIT_RESULTS"] != nil else { return }
        lock.lock(); defer { lock.unlock() }
        if !registered {
            XCTestObservationCenter.shared.addTestObserver(self)
            registered = true
        }
        vectorForTest[testCase.name] = stem
    }

    // MARK: XCTestObservation

    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        lock.lock(); defer { lock.unlock() }
        failedTests.insert(testCase.name)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        lock.lock(); defer { lock.unlock() }
        guard let stem = vectorForTest[testCase.name] else { return }
        let green = !failedTests.contains(testCase.name)
        // If a stem somehow runs across >1 test, AND the results (a regression in any → red).
        results[stem] = (results[stem] ?? true) && green
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        guard let path = ProcessInfo.processInfo.environment["TTD_EMIT_RESULTS"] else { return }
        lock.lock(); defer { lock.unlock() }
        let payload: [String: Any] = ["platform": "macos", "vectors": results]
        guard let data = try? JSONSerialization.data(withJSONObject: payload,
                                                     options: [.sortedKeys, .prettyPrinted]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("conformance-results → \(path) (\(results.count) vectors)\n".utf8))
    }
}

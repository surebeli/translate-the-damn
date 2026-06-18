import XCTest
@testable import TranslateTheDamnCore

/// Conformance for `pipeline-cache.json`: stateful — replay each scenario's `steps` through a FRESH
/// pipeline + fake translator that records call-count. `expectModelCall=true` ⇒ cache miss (model
/// invoked); `false` ⇒ served from the one-entry cache. Cache key = text + backend + model; only
/// successful results cached.
final class PipelineCacheTests: XCTestCase {
    func testPipelineCache() throws {
        let dir = try XCTUnwrap(ConformanceHarness.locateConformanceDir(),
                                "could not locate repo-root conformance/ from #file")
        let vec = try XCTUnwrap(ConformanceHarness.loadVector("pipeline-cache.json", dir, self))
        let scenarios = try XCTUnwrap(vec["scenarios"] as? [[String: Any]])

        for sc in scenarios {
            let name = (sc["name"] as? String) ?? "?"
            let backend = try XCTUnwrap(sc["backend"] as? String, "[\(name)] missing backend")
            let steps = try XCTUnwrap(sc["steps"] as? [[String: Any]], "[\(name)] missing steps")

            // Fresh pipeline + fake per scenario (the cache is one-entry and per-pipeline).
            let fake = FakeTranslator()
            let pipeline = TranslationPipeline(backend: backend, translator: fake)

            for (i, step) in steps.enumerated() {
                let text = try XCTUnwrap(step["text"] as? String, "[\(name)] step \(i) missing text")
                let model = try XCTUnwrap(step["model"] as? String, "[\(name)] step \(i) missing model")
                let expectModelCall = try XCTUnwrap(step["expectModelCall"] as? Bool,
                                                    "[\(name)] step \(i) missing expectModelCall")

                let before = fake.calls
                _ = pipeline.run(text: text, model: model)
                let delta = fake.calls - before
                XCTAssertEqual(delta, expectModelCall ? 1 : 0,
                               "pipeline-cache [\(name)] step \(i) (\(expectModelCall ? "miss" : "hit"))")
            }
        }
    }
}

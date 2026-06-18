import Foundation
@testable import TranslateTheDamnCore

/// Records every `translate` call so the `pipeline-cache` runner can compare the per-step call-count
/// delta to `expectModelCall`. Returns a deterministic successful result (cacheable) so the real M2
/// pipeline would populate its one-entry cache on the first step of an identical sequence.
final class FakeTranslator: Translator {
    private(set) var calls = 0

    func translate(text: String, model: String) -> TranslationResult {
        calls += 1
        return .successful("T:\(text)")
    }
}

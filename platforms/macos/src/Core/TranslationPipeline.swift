import Foundation

/// A translator the pipeline can drive. In M3 the real backends conform; in the conformance runner a
/// fake records whether it was called (the `pipeline-cache` vector). `translate` is synchronous here
/// — the pure cache logic under test has no async needs; the App layer wraps real (async) backends.
public protocol Translator {
    func translate(text: String, model: String) -> TranslationResult
}

/// Outcome of one translation. Only successful results are cached (mirrors the Windows pipeline).
public enum TranslateStatus: String, Equatable {
    case success
    case authFail
    case timeout
    case notFound
    case badOutput
    case unknownFail
}

public struct TranslationResult: Equatable {
    public var ok: Bool
    public var text: String
    public var status: TranslateStatus
    public var detail: String

    public init(ok: Bool, text: String, status: TranslateStatus = .success, detail: String = "") {
        self.ok = ok
        self.text = text
        self.status = status
        self.detail = detail
    }

    public static func successful(_ text: String) -> TranslationResult { TranslationResult(ok: true, text: text) }
    public static func failure(_ text: String) -> TranslationResult { TranslationResult(ok: false, text: text, status: .unknownFail) }
    public static func failed(_ status: TranslateStatus, _ detail: String) -> TranslationResult { TranslationResult(ok: false, text: detail, status: status, detail: detail) }
}

/// Orchestrates one translation with a one-entry "last successful translation" cache. Cache key =
/// text + backend + model; a hit returns the cached result without invoking the model. A different
/// backend/model is a different key ⇒ re-translate. Only successful results are cached (failures
/// never populate the cache, so a retry always hits the model).
public final class TranslationPipeline {
    private let backend: String
    private let translator: Translator
    private var cache: CacheEntry?

    public init(backend: String, translator: Translator) {
        self.backend = backend
        self.translator = translator
        self.cache = nil
    }

    /// Look up the one-entry cache; if it matches (text + backend + model), return the cached
    /// result without calling the translator. Otherwise invoke the translator and, on success,
    /// populate the cache.
    public func run(text: String, model: String) -> TranslationResult {
        if let cache = cache,
           cache.text == text,
           cache.backend == backend,
           cache.model == model {
            return cache.result
        }
        let result = translator.translate(text: text, model: model)
        if result.ok {
            cache = CacheEntry(text: text, backend: backend, model: model, result: result)
        }
        return result
    }

    private struct CacheEntry {
        let text: String
        let backend: String
        let model: String
        let result: TranslationResult
    }
}

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

/// Orchestrates one translation with a **recent-translation cache** (up to 5 entries, spec §4.1).
/// Cache key = text + backend + model. On a hit the cached result is returned without invoking the
/// model and the entry is promoted to most-recent (recency refresh). On a miss the model runs and a
/// successful result is inserted at the front; when the cache exceeds `cacheCapacity` the
/// least-recently-used entry is evicted. Only successful results are cached (failures never
/// populate it, so a retry always hits the model). `recentHistory()` exposes the entries
/// newest→oldest for the popup's history navigation (§8).
public final class TranslationPipeline {
    /// Max recent successful translations retained.
    public static let cacheCapacity = 5

    private let backend: String
    private let translator: Translator
    private var cache: [CacheEntry] = []   // most-recently-used first

    public init(backend: String, translator: Translator) {
        self.backend = backend
        self.translator = translator
    }

    /// Search the recent-translation cache; on a hit (text + backend + model) return the cached
    /// result without calling the translator and promote it to most-recent. On a miss invoke the
    /// translator and, on success, insert at the front, evicting the least-recently-used entry when
    /// the cache exceeds `cacheCapacity`.
    public func run(text: String, model: String) -> TranslationResult {
        if let idx = cache.firstIndex(where: { $0.text == text && $0.backend == backend && $0.model == model }) {
            let entry = cache.remove(at: idx)
            cache.insert(entry, at: 0)   // refresh recency
            return entry.result
        }
        let result = translator.translate(text: text, model: model)
        if result.ok {
            cache.insert(CacheEntry(text: text, backend: backend, model: model, result: result), at: 0)
            if cache.count > Self.cacheCapacity {
                cache.removeLast()
            }
        }
        return result
    }

    /// Recent successful translations, newest → oldest (drives the popup's history navigation).
    public func recentHistory() -> [(source: String, translation: String)] {
        cache.map { ($0.text, $0.result.text) }
    }

    private struct CacheEntry {
        let text: String
        let backend: String
        let model: String
        let result: TranslationResult
    }
}

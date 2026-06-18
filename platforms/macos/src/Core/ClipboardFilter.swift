import Foundation

/// Pure, injectable clipboard pipeline filters (spec §4.1).
/// Keeps no AppKit/NSPasteboard dependency so the logic is unit-testable on any Swift host.
public final class ClipboardFilter {
    public let maxChars: Int
    public let debounceIntervalMs: Int
    private let clock: () -> Date

    private var lastProcessedText: String?
    private var lastProcessedAt: Date?
    private var selfWriteHashes: Set<String> = []

    /// - Parameters:
    ///   - maxChars: hard upper bound on text length (e.g. `translation.maxChars`).
    ///   - debounceIntervalMs: minimum milliseconds between accepted changes.
    ///   - clock: injectable time source for deterministic tests.
    public init(maxChars: Int, debounceIntervalMs: Int = 250, clock: @escaping () -> Date = Date.init) {
        self.maxChars = maxChars
        self.debounceIntervalMs = debounceIntervalMs
        self.clock = clock
    }

    /// Returns `true` only when `newText` passes every pipeline filter.
    /// Side effect: a rejected self-write is consumed (so a later legitimate paste with the same
    /// text is not blocked forever).
    public func shouldProcess(newText: String) -> Bool {
        guard Self.shouldProcess(newText: newText, lastProcessed: lastProcessedText, maxChars: maxChars) else {
            return false
        }
        guard !isSelfWrite(text: newText) else { return false }
        guard debounceAllow() else { return false }
        return true
    }

    /// Records that `text` has just been translated, so the next identical paste is deduped
    /// and the debounce window starts from now.
    public func markProcessed(text: String) {
        lastProcessedText = text
        lastProcessedAt = clock()
    }

    /// Call before the app writes `text` to the pasteboard (copy-button / overwrite mode).
    /// The next clipboard change matching this text will be ignored exactly once.
    public func markSelfWrite(text: String) {
        selfWriteHashes.insert(Self.hash(text))
    }

    /// Returns `true` when `text` matches a pending self-write guard, consuming that guard.
    public func isSelfWrite(text: String) -> Bool {
        let hash = Self.hash(text)
        if selfWriteHashes.contains(hash) {
            selfWriteHashes.remove(hash)
            return true
        }
        return false
    }

    /// Pure filter stage: empty/whitespace, length cap, and consecutive-duplicate checks.
    /// Exposed as a static helper so unit tests can drive it without instantiating state.
    public static func shouldProcess(newText: String, lastProcessed: String?, maxChars: Int) -> Bool {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard newText.count <= maxChars else { return false }
        if let last = lastProcessed, last == newText { return false }
        return true
    }

    /// Stable hash used by the self-write guard. SHA-256 is unnecessary; a deterministic
    /// polynomial rolling hash over UTF-8 bytes is sufficient and avoids external dependencies.
    public static func hash(_ text: String) -> String {
        var h = 0
        for byte in text.utf8 {
            h = h &* 31 &+ Int(byte)
        }
        return String(h)
    }

    private func debounceAllow() -> Bool {
        let now = clock()
        if let last = lastProcessedAt,
           now.timeIntervalSince(last) * 1000 < Double(debounceIntervalMs) {
            return false
        }
        lastProcessedAt = now
        return true
    }
}

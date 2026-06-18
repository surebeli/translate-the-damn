import AppKit
import Foundation
import TranslateTheDamnCore

/// macOS clipboard watcher. There is no public clipboard-change event on macOS, so we poll
/// `NSPasteboard.general.changeCount` on a ~250 ms timer and feed text that passes the pipeline
/// filters into the translation pipeline via `onText`.
public final class ClipboardWatcher {
    private let pasteboard: NSPasteboard
    private let filter: ClipboardFilter
    private let interval: TimeInterval
    private let onText: (String) -> Void

    private var timer: Timer?
    private var lastChangeCount: Int
    private var isListening: Bool = false

    /// - Parameters:
    ///   - pasteboard: the pasteboard to watch (`.general` in production, injectable in tests).
    ///   - filter: pipeline filters (max chars, dedupe, debounce, self-write guard).
    ///   - interval: polling interval in seconds; default ~250 ms.
    ///   - onText: callback invoked for each accepted clipboard text.
    public init(
        pasteboard: NSPasteboard = .general,
        filter: ClipboardFilter,
        interval: TimeInterval = 0.25,
        onText: @escaping (String) -> Void
    ) {
        self.pasteboard = pasteboard
        self.filter = filter
        self.interval = interval
        self.onText = onText
        self.lastChangeCount = pasteboard.changeCount
    }

    public var listening: Bool { isListening }

    public func start() {
        guard !isListening else { return }
        isListening = true
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    public func stop() {
        isListening = false
        timer?.invalidate()
        timer = nil
    }

    /// Records a text the app is about to write to the clipboard so the resulting change is ignored.
    public func markSelfWrite(_ text: String) {
        filter.markSelfWrite(text: text)
    }

    private func tick() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let text = pasteboard.string(forType: .string) else { return }
        guard filter.shouldProcess(newText: text) else { return }

        filter.markProcessed(text: text)
        onText(text)
    }
}

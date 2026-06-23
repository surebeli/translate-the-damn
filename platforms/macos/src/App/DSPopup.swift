import AppKit
import Foundation
import TranslateTheDamnCore

/// DS-style translation popup — a *clean glass card with italic accents*.
///
/// Design identity (distinct from all six existing styles):
///   • acrylic → `.popover` vibrancy behind-window — a lightweight glass card.
///   • solid   → opaque `.contentBackground` material with adaptive appearance.
///   • No accent rails or lines — the material itself defines the boundary.
///   • Source text is rendered in *italic* — no other style does this.
///   • Header is a simple label + spinner; no status icon glyph.
///   • Body text is 14pt with comfortable 3pt line spacing.
///   • Primary action ("copy") is a pill-shaped accent button (cornerRadius 9);
///     "close" stays quiet.
///   • Entrance/exit is a symmetric rise + fade (0.2s).
///
/// Non-focus-stealing: NSPanel(.nonactivatingPanel) + canBecomeKey/Main = false + .floating.
/// Honors every PopupConfig field (style, autoDismissSeconds, keepOnHover).
/// One entry in the popup's recent-translation history (source + its translation).
struct PopupHistoryEntry {
    let source: String
    let translation: String
}

/// Common protocol for the translation popup (kept after consolidating to a single UI;
/// originally declared in the now-removed ZPPopup.swift).
@MainActor
protocol TranslationPopupUI: AnyObject {
    func showLoading()
    func showResult(translation: String, source: String)
    /// Show a result with browsable history (newest first); `index` is the entry to display
    /// (0 = newest = just-queried). The popup adds ◀ ▶ navigation when history has >1 entry.
    func showResults(_ history: [PopupHistoryEntry], index: Int)
    func showError(message: String)
    func show(source: String, translation: String)
    func update(translation: String)
    func dismiss()
}

final class DSPopup: NSPanel, TranslationPopupUI {
    private let cfg: PopupConfig
    private let onCopy: (String) -> Void

    private let visualEffectView = NSVisualEffectView()
    private let contentStack = NSStackView()
    private let headerStack = NSStackView()
    private let headerSpinner = NSProgressIndicator()
    private let headerLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")   // backend source — header right (mirrors Windows StatusText)
    private let headerSpacer = NSView()
    private let sourceLabel = NSTextField(labelWithString: "")

    /// The backend that produced the translation, shown dimmed at the header's right edge — the
    /// translation-source hint the Windows popup already has (StatusText = backendId).
    var backendName: String = "" {
        didSet { statusLabel.stringValue = backendName; statusLabel.isHidden = backendName.isEmpty }
    }
    private let translationScrollView = NSScrollView()
    private let translationTextView = NSTextView()
    private let buttonStack = NSStackView()
    private let copyButton = DSPrimaryButton(frame: .zero)
    private let closeButton = NSButton(title: "", target: nil, action: nil)

    private var dismissTimer: Timer?
    private var copiedTimer: Timer?
    private var isMouseOver = false
    private var currentTranslation = ""

    // Session-sticky drag position (spec §8 "Drag to reposition" shared rule). Static so it survives
    // the panel being recreated on every show (AppDelegate rebuilds DSPopup each time); in-memory
    // only, so it resets to top-center on app restart. nil until the user performs a REAL drag.
    // Mirrors Windows `PopupWindow._userPosition`.
    private static var sessionOrigin: NSPoint?
    // Filters our own placement (showAndPlace / the show animation) out of the move notifications, so
    // programmatic positioning is never mistaken for a user drag.
    private var isProgrammaticMove = false

    // History navigation (spec §4.1 / §8): browse the recent-translation cache, one entry at a time.
    private let prevButton = NSButton(title: "", target: nil, action: nil)   // ◀ older
    private let nextButton = NSButton(title: "", target: nil, action: nil)   // ▶ newer
    private let historyIndicator = NSTextField(labelWithString: "")
    private var history: [PopupHistoryEntry] = []
    private var currentIndex = 0

    // Adaptive size (spec §8): EXACTLY two fixed window specs — normal, and large = 2× width ×
    // 1.5× height. The window always snaps to one of these two; the source (≤2 lines) and the
    // scrollable translation adapt INSIDE, so different source lengths never make a third size.
    private let normalWindowSize = NSSize(width: 390, height: 340)
    private var largeWindowSize: NSSize {
        NSSize(width: normalWindowSize.width * CGFloat(PopupSizing.largeWidthFactor),
               height: normalWindowSize.height * CGFloat(PopupSizing.largeHeightFactor))
    }
    private let contentInsetX: CGFloat = 40   // contentStack left(20) + right(20) insets
    private var isLargeSize = false
    private var scrollWidthConstraint: NSLayoutConstraint!
    private var sourceWidthConstraint: NSLayoutConstraint!
    private var headerWidthConstraint: NSLayoutConstraint!

    private func innerWidth(forLarge large: Bool) -> CGFloat {
        (large ? largeWindowSize.width : normalWindowSize.width) - contentInsetX
    }

    init(cfg: PopupConfig, onCopy: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onCopy = onCopy

        let style: NSWindow.StyleMask = [.nonactivatingPanel, .titled, .fullSizeContentView, .borderless]
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 220), styleMask: style, backing: .buffered, defer: false)

        setUpWindow()
        setUpContent()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Window

    private func setUpWindow() {
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true   // drag the card background to reposition (spec §8)
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        contentView = visualEffectView

        // Drag-to-reposition wiring (spec §8): pause auto-dismiss while the user drags the card, and
        // on settle remember the spot (session-sticky) + restart the timer. The action buttons / text
        // view consume their own mouse events, so background drag never fires on them. canBecomeKey =
        // false keeps the drag from stealing focus (the macOS analog of WS_EX_NOACTIVATE).
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillMove),
                                               name: NSWindow.willMoveNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidMove),
                                               name: NSWindow.didMoveNotification, object: self)
    }

    // MARK: - Content

    private func setUpContent() {
        visualEffectView.blendingMode = .behindWindow
        if cfg.style == "solid" {
            visualEffectView.material = .contentBackground
            visualEffectView.state = .inactive
            visualEffectView.appearance = nil
        } else {
            visualEffectView.material = .popover
            visualEffectView.state = .active
            visualEffectView.appearance = nil
        }
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 12
        visualEffectView.layer?.masksToBounds = true

        // Content stack — no accent rail, the card stands on its own.
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.distribution = .fill   // the scroll view (lowest hugging) absorbs vertical slack
        contentStack.spacing = 10
        contentStack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 14, right: 20)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
        ])

        // Header: spinner + title (no icon — cleaner, distinct from MM/O48/Z).
        headerSpinner.style = .spinning
        headerSpinner.controlSize = .small
        headerSpinner.isDisplayedWhenStopped = false
        headerSpinner.isHidden = true

        headerLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .labelColor
        headerLabel.maximumNumberOfLines = 1

        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 7
        headerStack.addArrangedSubview(headerSpinner)
        headerStack.addArrangedSubview(headerLabel)
        // Backend source, pushed to the trailing edge (mirrors Windows StatusText = backendId).
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.maximumNumberOfLines = 1
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isHidden = true
        statusLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerStack.addArrangedSubview(headerSpacer)
        headerStack.addArrangedSubview(statusLabel)
        contentStack.addArrangedSubview(headerStack)
        headerWidthConstraint = headerStack.widthAnchor.constraint(equalToConstant: innerWidth(forLarge: false))
        headerWidthConstraint.isActive = true

        // Source (italic, muted, two lines max — the DS signature).
        sourceLabel.font = NSFont.systemFont(ofSize: 11)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.maximumNumberOfLines = 2
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.preferredMaxLayoutWidth = innerWidth(forLarge: false)
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sourceWidthConstraint = sourceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: innerWidth(forLarge: false))
        sourceWidthConstraint.isActive = true
        contentStack.addArrangedSubview(sourceLabel)

        // Translation (scrollable, 14pt, 3pt line spacing). FIXED width per size class but FLEXIBLE
        // height (lowest hugging) — it absorbs all vertical slack so the window stays exactly the
        // fixed spec; source/translation length only changes how much scroll area there is.
        translationScrollView.translatesAutoresizingMaskIntoConstraints = false
        translationScrollView.hasVerticalScroller = true
        translationScrollView.hasHorizontalScroller = false
        translationScrollView.borderType = .noBorder
        translationScrollView.drawsBackground = false
        translationScrollView.autohidesScrollers = true
        translationScrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        translationScrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scrollWidthConstraint = translationScrollView.widthAnchor.constraint(equalToConstant: innerWidth(forLarge: false))
        scrollWidthConstraint.isActive = true

        translationTextView.isEditable = false
        translationTextView.isSelectable = true
        translationTextView.drawsBackground = false
        translationTextView.textContainerInset = NSSize(width: 0, height: 4)
        translationTextView.isRichText = false
        translationTextView.usesAdaptiveColorMappingForDarkAppearance = true
        translationScrollView.documentView = translationTextView
        contentStack.addArrangedSubview(translationScrollView)

        // Buttons (right-aligned: close, then pill accent copy).
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 10
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fill
        contentStack.addArrangedSubview(buttonStack)
        buttonStack.widthAnchor.constraint(equalTo: translationScrollView.widthAnchor).isActive = true

        // History nav (left side): ◀ older · "i / n" · ▶ newer. Hidden unless >1 cached entry.
        configureNavButton(prevButton, symbol: "chevron.left", tip: StringsLoader["popup.nav.older"], action: #selector(onPrev))
        configureNavButton(nextButton, symbol: "chevron.right", tip: StringsLoader["popup.nav.newer"], action: #selector(onNext))
        historyIndicator.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        historyIndicator.textColor = .secondaryLabelColor
        prevButton.isHidden = true
        nextButton.isHidden = true
        historyIndicator.isHidden = true
        buttonStack.addArrangedSubview(prevButton)
        buttonStack.addArrangedSubview(historyIndicator)
        buttonStack.addArrangedSubview(nextButton)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        buttonStack.addArrangedSubview(spacer)

        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .regular
        closeButton.font = NSFont.systemFont(ofSize: 12)
        closeButton.title = StringsLoader["popup.button.close"]
        closeButton.target = self
        closeButton.action = #selector(onCloseButton)
        buttonStack.addArrangedSubview(closeButton)

        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        copyButton.target = self
        copyButton.action = #selector(onCopyButton)
        copyButton.isHidden = true
        buttonStack.addArrangedSubview(copyButton)

        // Hover tracking.
        let trackingArea = NSTrackingArea(
            rect: visualEffectView.bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        visualEffectView.addTrackingArea(trackingArea)
    }

    // MARK: - States

    func showLoading() {
        setHeader(title: StringsLoader["popup.header.translating"], loading: true)
        sourceLabel.stringValue = ""
        sourceLabel.isHidden = true
        setBody(StringsLoader["popup.body.translating"], color: .secondaryLabelColor)
        copyButton.isHidden = true
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        history = []
        setHistoryControlsHidden()
        applySize(sourceChars: 0)
        dismissTimer?.invalidate()
        dismissTimer = nil
        showAndPlace()
    }

    func showResult(translation: String, source: String) {
        showResults([PopupHistoryEntry(source: source, translation: translation)], index: 0)
    }

    func showResults(_ history: [PopupHistoryEntry], index: Int) {
        self.history = history
        self.currentIndex = index
        renderCurrent()
        if !isMouseOver { restartDismiss() }
    }

    /// Render the currently selected history entry: source + translation, nav controls, and size
    /// (large when this entry's source > 500 chars). Reused by showResults and ◀/▶ navigation.
    private func renderCurrent() {
        guard !history.isEmpty else { return }
        currentIndex = min(max(currentIndex, 0), history.count - 1)
        let entry = history[currentIndex]
        currentTranslation = entry.translation
        setHeader(title: StringsLoader["popup.header.result"], loading: false)
        let trimmedSource = truncate(entry.source, max: 400)
        sourceLabel.attributedStringValue = italicString(trimmedSource)
        sourceLabel.isHidden = trimmedSource.isEmpty
        setBody(entry.translation, color: .labelColor)
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        copyButton.isHidden = false
        updateHistoryControls()
        applySize(sourceChars: entry.source.count)
        translationScrollView.contentView.scroll(to: .zero)
        showAndPlace()
    }

    private func updateHistoryControls() {
        let multi = history.count > 1
        prevButton.isHidden = !multi
        nextButton.isHidden = !multi
        historyIndicator.isHidden = !multi
        guard multi else { return }
        historyIndicator.stringValue = "\(currentIndex + 1) / \(history.count)"
        prevButton.isEnabled = currentIndex < history.count - 1   // an older entry exists
        nextButton.isEnabled = currentIndex > 0                   // a newer entry exists
    }

    private func setHistoryControlsHidden() {
        prevButton.isHidden = true
        nextButton.isHidden = true
        historyIndicator.isHidden = true
    }

    /// Pick one of the two fixed size specs from the displayed entry's source length (§8). Only the
    /// inner WIDTH is constrained here; the window snaps to the exact spec in showAndPlace().
    private func applySize(sourceChars: Int) {
        isLargeSize = PopupSizing.sizeClass(sourceChars: sourceChars) == "large"
        let w = innerWidth(forLarge: isLargeSize)
        scrollWidthConstraint.constant = w
        sourceWidthConstraint.constant = w
        headerWidthConstraint.constant = w
        sourceLabel.preferredMaxLayoutWidth = w
    }

    private func configureNavButton(_ b: NSButton, symbol: String, tip: String, action: Selector) {
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.imagePosition = .imageOnly
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.toolTip = tip
        b.target = self
        b.action = action
    }

    @objc private func onPrev() {   // ◀ older
        guard currentIndex < history.count - 1 else { return }
        currentIndex += 1
        renderCurrent()
        if !isMouseOver { restartDismiss() }
    }

    @objc private func onNext() {   // ▶ newer
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        renderCurrent()
        if !isMouseOver { restartDismiss() }
    }

    func showError(message: String) {
        // Hard failure → red on BOTH header and body (was: black header + orange body, which read as
        // a warning and gave the error no header-level signal).
        setHeader(title: StringsLoader["popup.header.error"], loading: false, color: .systemRed)
        sourceLabel.stringValue = ""
        sourceLabel.isHidden = true
        setBody(message, color: .systemRed)
        copyButton.isHidden = true
        history = []
        setHistoryControlsHidden()
        applySize(sourceChars: 0)
        showAndPlace()
        if !isMouseOver { restartDismiss() }
    }

    func show(source: String, translation: String) {
        showResult(translation: translation, source: source)
    }

    func update(translation: String) {
        currentTranslation = translation
        setBody(translation, color: .labelColor)
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        copyButton.isHidden = false
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        copiedTimer?.invalidate()
        copiedTimer = nil
        let origin = frame.origin
        NSAnimationContext.runAnimationGroup { [weak self] ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self?.animator().alphaValue = 0
            self?.animator().setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 10))
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.orderOut(nil)
                self?.alphaValue = 1.0
            }
        }
    }

    // MARK: - Header / body helpers

    private func setHeader(title: String, loading: Bool, color: NSColor = .labelColor) {
        headerLabel.stringValue = title
        headerLabel.textColor = color
        if loading {
            headerSpinner.isHidden = false
            headerSpinner.startAnimation(nil)
        } else {
            headerSpinner.stopAnimation(nil)
            headerSpinner.isHidden = true
        }
    }

    private func setBody(_ text: String, color: NSColor) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: color,
            .paragraphStyle: para,
        ]
        translationTextView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
        translationTextView.typingAttributes = attrs
    }

    private func italicString(_ s: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 11)
        let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        return NSAttributedString(string: s, attributes: [
            .font: italicFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    private func accentTitle(_ s: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        return NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ])
    }

    // MARK: - Placement / animation

    private func showAndPlace() {
        // Snap to exactly ONE of the two fixed specs (NOT fittingSize) so different source lengths
        // and ◀▶ navigation only ever switch between normal ↔ large — never an in-between size.
        setContentSize(isLargeSize ? largeWindowSize : normalWindowSize)
        visualEffectView.layoutSubtreeIfNeeded()

        // Session-sticky: reuse the user's dragged spot (clamped on-screen) if they moved it this
        // session; otherwise top-center. isProgrammaticMove filters these placements out of the
        // move-notification handlers below.
        let target = clampToVisible(Self.sessionOrigin ?? topCenterOrigin())
        isProgrammaticMove = true
        if !isVisible {
            alphaValue = 0
            setFrameOrigin(NSPoint(x: target.x, y: target.y - 10))
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 1.0
                self.animator().setFrameOrigin(target)
            }, completionHandler: { [weak self] in
                self?.isProgrammaticMove = false
            })
        } else {
            alphaValue = 1.0
            setFrameOrigin(target)
            isProgrammaticMove = false
        }
    }

    private func topCenterOrigin() -> NSPoint {
        guard let screen = NSScreen.screens.first else { return .zero }
        let visibleFrame = screen.visibleFrame
        let f = self.frame
        let x = visibleFrame.midX - f.width / 2
        let y = visibleFrame.maxY - f.height - 12
        return NSPoint(x: x, y: y)
    }

    private func restartDismiss() {
        dismissTimer?.invalidate()
        let seconds = cfg.autoDismissSeconds
        if seconds > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { [weak self] _ in
                DispatchQueue.main.async { self?.dismiss() }
            }
        }
    }

    private func truncate(_ s: String, max: Int) -> String {
        s.count > max ? String(s.prefix(max)) + "…" : s
    }

    // MARK: - Hover

    override func mouseEntered(with event: NSEvent) {
        isMouseOver = true
        if cfg.keepOnHover { dismissTimer?.invalidate() }
    }

    override func mouseExited(with event: NSEvent) {
        isMouseOver = false
        if cfg.keepOnHover { restartDismiss() }
    }

    // MARK: - Drag (session-sticky reposition, spec §8)

    @objc private func handleWillMove(_ note: Notification) {
        guard !isProgrammaticMove else { return }   // ignore our own placement
        dismissTimer?.invalidate()                  // pause auto-dismiss while dragging
    }

    @objc private func handleDidMove(_ note: Notification) {
        guard !isProgrammaticMove else { return }
        // A REAL user drag (a plain click never moves the window, so this never fires on a tap):
        // remember the spot for later popups this session, and restart the dismiss countdown — which,
        // because didMove fires per move step, only elapses fully after the last move = on drop.
        Self.sessionOrigin = clampToVisible(frame.origin)
        restartDismiss()
    }

    private func clampToVisible(_ origin: NSPoint) -> NSPoint {
        guard let screen = NSScreen.screens.first else { return origin }
        let vf = screen.visibleFrame
        let f = self.frame
        let x = min(max(origin.x, vf.minX), vf.maxX - f.width)
        let y = min(max(origin.y, vf.minY), vf.maxY - f.height)
        return NSPoint(x: x, y: y)
    }

    // MARK: - Actions

    @objc private func onCopyButton() {
        guard !currentTranslation.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentTranslation, forType: .string)
        onCopy(currentTranslation)
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copied"])
        copiedTimer?.invalidate()
        copiedTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.copyButton.attributedTitle = self.accentTitle(StringsLoader["popup.button.copy"])
            }
        }
    }

    @objc private func onCloseButton() {
        dismiss()
    }
}

/// Pill-shaped accent primary button for DS popup.
///
/// In a non-key panel (`canBecomeKey = false`), AppKit does not render the default
/// accent/bezel-color treatment — a stock accent button would look like a plain gray
/// secondary button. This draws the accent fill on its own layer (with vibrancy disabled)
/// so the primary action always reads as primary.
private final class DSPrimaryButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        applyAccent()
    }

    private func applyAccent() {
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    }

    override var allowsVibrancy: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAccent()
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 32
        size.height = 28
        return size
    }
}

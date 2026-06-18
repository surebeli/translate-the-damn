import AppKit
import Foundation
import TranslateTheDamnCore

/// Z-style translation popup — a *document card*.
///
/// Design identity (distinct from Classic / ZP / O48 / KM):
///   • Hairline-bordered rounded card (18pt radius, `separatorColor` stroke) — definition by
///     outline, not a filled accent rail (O48 = leading rail, KM = top rail, ZP/Classic = none).
///   • acrylic → `.sidebar` active vibrancy (a calm adaptive frost, distinct from ZP/KM's
///     `.popover` and O48's pinned-dark `.hudWindow`); solid → opaque `.windowBackground`.
///     Adaptive appearance throughout — Z is never force-dark (that's O48's signature).
///   • A status pill in the header: a tinted capsule with a status dot (or a spinner while
///     loading) + the status word — distinct from ZP's plain label, O48's symbol+spinner, and
///     KM's uppercased secondary label.
///   • A char-count detail in the footer ("N 字") — an editor-card touch none of the others have.
///   • Primary action ("copy") is an accent-filled `ZPrimaryButton` (vibrancy disabled) so it
///     always reads as primary inside a non-key panel — the same lesson O48/KM learned.
///   • Calm symmetric fade (0.2s); the composition carries the identity, so motion stays quiet.
///
/// Honors every `PopupConfig` field (`style`, `autoDismissSeconds`, `keepOnHover`) and stays
/// non-focus-stealing: NSPanel(.nonactivatingPanel) + canBecomeKey/Main=false + .floating level.
final class ZPopup: NSPanel, TranslationPopupUI {
    private let cfg: PopupConfig
    private let onCopy: (String) -> Void

    private let visualEffectView = ZCardView()
    private let contentStack = NSStackView()
    private let headerRow = NSStackView()
    private let statusPill = ZStatusPill()
    private let sourceLabel = NSTextField(labelWithString: "")
    private let translationScrollView = NSScrollView()
    private let translationTextView = NSTextView()
    private let footerRow = NSStackView()
    private let charCountLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "", target: nil, action: nil)
    private let copyButton = ZPrimaryButton(frame: .zero)

    private var dismissTimer: Timer?
    private var copiedTimer: Timer?
    private var isMouseOver = false
    private var currentTranslation = ""

    private let scrollWidth: CGFloat = 336

    init(cfg: PopupConfig, onCopy: @escaping (String) -> Void) {
        self.cfg = cfg
        self.onCopy = onCopy

        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .titled, .fullSizeContentView, .borderless]
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 220), styleMask: styleMask, backing: .buffered, defer: false)

        setUpWindow()
        setUpContent()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Window

    private func setUpWindow() {
        level = .floating
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        contentView = visualEffectView
    }

    // MARK: - Content

    private func setUpContent() {
        // Material — Z signature: calm sidebar frost (acrylic) vs opaque windowBackground (solid).
        visualEffectView.blendingMode = .behindWindow
        if cfg.style == "solid" {
            visualEffectView.material = .windowBackground
            visualEffectView.state = .inactive
            visualEffectView.appearance = nil
        } else {
            visualEffectView.material = .sidebar
            visualEffectView.state = .active
            visualEffectView.appearance = nil
        }
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 18
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.layer?.borderColor = NSColor.separatorColor.cgColor

        // Content stack.
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 16, right: 22)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
        ])

        // Header row — status pill on the leading edge.
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8
        headerRow.addArrangedSubview(statusPill)
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headerRow.addArrangedSubview(headerSpacer)
        contentStack.addArrangedSubview(headerRow)

        // Source (muted, two lines max, truncated).
        sourceLabel.font = NSFont.systemFont(ofSize: 11)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.maximumNumberOfLines = 2
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.preferredMaxLayoutWidth = scrollWidth
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sourceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: scrollWidth).isActive = true
        contentStack.addArrangedSubview(sourceLabel)

        // Translation (scrollable, 15pt, comfortable line spacing).
        let scrollHeight: CGFloat = min(cfg.autoDismissSeconds > 0 ? 200 : 280, 280)
        translationScrollView.translatesAutoresizingMaskIntoConstraints = false
        translationScrollView.hasVerticalScroller = true
        translationScrollView.hasHorizontalScroller = false
        translationScrollView.borderType = .noBorder
        translationScrollView.drawsBackground = false
        translationScrollView.autohidesScrollers = true
        translationScrollView.heightAnchor.constraint(equalToConstant: scrollHeight).isActive = true
        translationScrollView.widthAnchor.constraint(equalToConstant: scrollWidth).isActive = true

        translationTextView.isEditable = false
        translationTextView.isSelectable = true
        translationTextView.drawsBackground = false
        translationTextView.textContainerInset = NSSize(width: 0, height: 4)
        translationTextView.isRichText = false
        translationTextView.usesAdaptiveColorMappingForDarkAppearance = true
        translationScrollView.documentView = translationTextView
        contentStack.addArrangedSubview(translationScrollView)

        // Header/footer span the body width so the pill stays leading and actions stay trailing.
        headerRow.widthAnchor.constraint(equalTo: translationScrollView.widthAnchor).isActive = true

        // Footer row — char count + actions.
        footerRow.orientation = .horizontal
        footerRow.spacing = 10
        footerRow.alignment = .centerY
        footerRow.distribution = .fill
        contentStack.addArrangedSubview(footerRow)
        footerRow.widthAnchor.constraint(equalTo: translationScrollView.widthAnchor).isActive = true

        charCountLabel.font = NSFont.systemFont(ofSize: 11)
        charCountLabel.textColor = .tertiaryLabelColor
        charCountLabel.isHidden = true
        footerRow.addArrangedSubview(charCountLabel)

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footerRow.addArrangedSubview(footerSpacer)

        closeButton.bezelStyle = .rounded
        closeButton.controlSize = .small
        closeButton.font = NSFont.systemFont(ofSize: 11)
        closeButton.title = StringsLoader["popup.button.close"]
        closeButton.target = self
        closeButton.action = #selector(onCloseButton)
        footerRow.addArrangedSubview(closeButton)

        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        copyButton.target = self
        copyButton.action = #selector(onCopyButton)
        copyButton.isHidden = true
        footerRow.addArrangedSubview(copyButton)

        // Hover tracking for keep-on-hover.
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
        statusPill.set(status: StringsLoader["popup.header.translating"], color: .tertiaryLabelColor, loading: true)
        sourceLabel.stringValue = ""
        sourceLabel.isHidden = true
        setBody(StringsLoader["popup.body.translating"], color: .tertiaryLabelColor)
        charCountLabel.isHidden = true
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        copyButton.isHidden = true
        dismissTimer?.invalidate()
        dismissTimer = nil
        showAndPlace()
    }

    func showResult(translation: String, source: String) {
        currentTranslation = translation
        statusPill.set(status: StringsLoader["popup.header.result"], color: .controlAccentColor, loading: false)
        let trimmedSource = truncate(source, max: 400)
        sourceLabel.stringValue = trimmedSource
        sourceLabel.isHidden = trimmedSource.isEmpty
        setBody(translation, color: .labelColor)
        charCountLabel.stringValue = "\(translation.count) 字"
        charCountLabel.isHidden = false
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        copyButton.isHidden = false
        translationScrollView.contentView.scroll(to: .zero)
        showAndPlace()
        if !isMouseOver { restartDismiss() }
    }

    func showError(message: String) {
        statusPill.set(status: StringsLoader["popup.header.error"], color: .systemOrange, loading: false)
        sourceLabel.stringValue = ""
        sourceLabel.isHidden = true
        setBody(message, color: .systemOrange)
        charCountLabel.isHidden = true
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        copyButton.isHidden = true
        showAndPlace()
        if !isMouseOver { restartDismiss() }
    }

    func show(source: String, translation: String) {
        showResult(translation: translation, source: source)
    }

    func update(translation: String) {
        currentTranslation = translation
        setBody(translation, color: .labelColor)
        charCountLabel.stringValue = "\(translation.count) 字"
        charCountLabel.isHidden = false
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        copyButton.isHidden = false
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        copiedTimer?.invalidate()
        copiedTimer = nil
        NSAnimationContext.runAnimationGroup { [weak self] ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.orderOut(nil)
                self?.alphaValue = 1.0
            }
        }
    }

    // MARK: - Helpers

    private func setBody(_ text: String, color: NSColor) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: color,
            .paragraphStyle: para,
        ]
        translationTextView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
        translationTextView.typingAttributes = attrs
    }

    private func accentTitle(_ s: String) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        return NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ])
    }

    private func showAndPlace() {
        // Size the window to the current content BEFORE positioning. Content height varies between
        // states (the source line is hidden during loading/error, shown on a result), and AppKit's
        // auto-layout-driven window resize only settles on a later layout pass — reading self.frame
        // before that would mis-anchor the top edge on the loading→result transition. Forcing layout
        // + an explicit setContentSize makes top-center placement exact in every state.
        visualEffectView.layoutSubtreeIfNeeded()
        setContentSize(visualEffectView.fittingSize)

        let target = topCenterOrigin()
        if !isVisible {
            alphaValue = 0
            setFrameOrigin(target)
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 1.0
            }
        } else {
            alphaValue = 1.0
            setFrameOrigin(target)
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

/// The Z popup's vibrancy card. Owns the hairline border; re-resolves `separatorColor` on
/// appearance changes (separatorColor is dynamic — a cached cgColor would go stale on light/dark).
private final class ZCardView: NSVisualEffectView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.borderColor = NSColor.separatorColor.cgColor
    }
}

/// Tinted capsule carrying a status dot (or a spinner while loading) + the status word.
/// Fill = status color @ ~12% (a subtle tint); the dot carries the saturated status color; the
/// label stays `labelColor` so legibility is guaranteed on any tint/material (no hardcoded RGB).
private final class ZStatusPill: NSView {
    private let dot = NSView()
    private let spinner = NSProgressIndicator()
    private let label = NSTextField(labelWithString: "")
    private let inner = NSStackView()
    private var statusColor: NSColor = .tertiaryLabelColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true

        inner.orientation = .horizontal
        inner.alignment = .centerY
        inner.spacing = 6
        inner.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 10)
        inner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: topAnchor),
            inner.bottomAnchor.constraint(equalTo: bottomAnchor),
            inner.leadingAnchor.constraint(equalTo: leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 6).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 6).isActive = true
        inner.addArrangedSubview(dot)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        inner.addArrangedSubview(spinner)

        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        inner.addArrangedSubview(label)

        applyColors()
    }

    func set(status: String, color: NSColor, loading: Bool) {
        label.stringValue = status
        statusColor = color
        if loading {
            dot.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            dot.isHidden = false
        }
        applyColors()
    }

    private func applyColors() {
        layer?.backgroundColor = statusColor.withAlphaComponent(0.15).cgColor
        dot.layer?.backgroundColor = statusColor.cgColor
    }

    /// Disable vibrancy blending so the tinted capsule fill reads as drawn instead of being
    /// washed out by the .sidebar card's active vibrancy. The dot and label still adapt to
    /// light/dark via dynamic system colors (re-resolved in viewDidChangeEffectiveAppearance).
    override var allowsVibrancy: Bool { false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }
}

/// Filled-accent primary button that stays visually emphasized inside a non-key panel.
/// Default NSButton accent highlighting is ignored for non-key windows / vibrancy, so the accent
/// fill is drawn on its own layer with vibrancy disabled (mirrors O48/KM).
private final class ZPrimaryButton: NSButton {
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
        layer?.cornerRadius = 6
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
        size.width += 24
        size.height = 22
        return size
    }
}

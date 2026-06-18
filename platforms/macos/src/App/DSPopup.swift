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
final class DSPopup: NSPanel, TranslationPopupUI {
    private let cfg: PopupConfig
    private let onCopy: (String) -> Void

    private let visualEffectView = NSVisualEffectView()
    private let contentStack = NSStackView()
    private let headerStack = NSStackView()
    private let headerSpinner = NSProgressIndicator()
    private let headerLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let translationScrollView = NSScrollView()
    private let translationTextView = NSTextView()
    private let buttonStack = NSStackView()
    private let copyButton = DSPrimaryButton(frame: .zero)
    private let closeButton = NSButton(title: "", target: nil, action: nil)

    private var dismissTimer: Timer?
    private var copiedTimer: Timer?
    private var isMouseOver = false
    private var currentTranslation = ""

    private let scrollWidth: CGFloat = 350

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
        contentStack.addArrangedSubview(headerStack)

        // Source (italic, muted, two lines max — the DS signature).
        sourceLabel.font = NSFont.systemFont(ofSize: 11)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.maximumNumberOfLines = 2
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.preferredMaxLayoutWidth = scrollWidth
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sourceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: scrollWidth).isActive = true
        contentStack.addArrangedSubview(sourceLabel)

        // Translation (scrollable, 14pt, 3pt line spacing).
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

        // Buttons (right-aligned: close, then pill accent copy).
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 10
        buttonStack.alignment = .centerY
        buttonStack.distribution = .fill
        contentStack.addArrangedSubview(buttonStack)
        buttonStack.widthAnchor.constraint(equalTo: translationScrollView.widthAnchor).isActive = true

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
        setBody(StringsLoader["popup.body.translating"], color: .tertiaryLabelColor)
        copyButton.isHidden = true
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        dismissTimer?.invalidate()
        dismissTimer = nil
        showAndPlace()
    }

    func showResult(translation: String, source: String) {
        currentTranslation = translation
        setHeader(title: StringsLoader["popup.header.result"], loading: false)
        let trimmedSource = truncate(source, max: 400)
        sourceLabel.attributedStringValue = italicString(trimmedSource)
        sourceLabel.isHidden = trimmedSource.isEmpty
        setBody(translation, color: .labelColor)
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        copyButton.isHidden = false
        translationScrollView.contentView.scroll(to: .zero)
        showAndPlace()
        if !isMouseOver { restartDismiss() }
    }

    func showError(message: String) {
        setHeader(title: StringsLoader["popup.header.error"], loading: false)
        sourceLabel.stringValue = ""
        sourceLabel.isHidden = true
        setBody(message, color: .systemOrange)
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

    private func setHeader(title: String, loading: Bool) {
        headerLabel.stringValue = title
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
        visualEffectView.layoutSubtreeIfNeeded()
        setContentSize(visualEffectView.fittingSize)

        let target = topCenterOrigin()
        if !isVisible {
            alphaValue = 0
            setFrameOrigin(NSPoint(x: target.x, y: target.y - 10))
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().alphaValue = 1.0
                self.animator().setFrameOrigin(target)
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

import AppKit
import Foundation
import TranslateTheDamnCore

/// O48-style translation popup — a *focused translation HUD*.
///
/// Design identity (distinct from ZP's adaptive popover and the Classic dark-scrim panel):
///   • acrylic → `.hudWindow` vibrancy pinned to a `.vibrantDark` appearance — the signature
///     Spotlight-style focused HUD. Always-dark + vibrant; system semantic colors resolve light
///     against the vibrant-dark context so legibility is guaranteed by construction.
///   • solid   → opaque `.windowBackground` material with the *adaptive* system appearance
///     (follows light/dark). No hand-rolled colors anywhere.
///   • A leading accent rail (`controlAccentColor`) brands every state.
///   • Header carries an SF Symbol status glyph + an inline spinner for the loading state.
///   • Body text is 16pt with comfortable line spacing for reading.
///   • Primary action ("copy") is an accent-tinted button; "close" stays quiet.
///   • Entrance/exit is a symmetric rise + fade (0.2s), not a plain cross-fade.
///
/// Non-focus-stealing, exactly like ZP/Classic: NSPanel(.nonactivatingPanel) +
/// canBecomeKey/Main = false + .floating level. Honors every `PopupConfig` field
/// (`style`, `autoDismissSeconds`, `keepOnHover`).
final class O48Popup: NSPanel, TranslationPopupUI {
    private let cfg: PopupConfig
    private let onCopy: (String) -> Void

    // Layout
    private let visualEffectView = NSVisualEffectView()
    private let accentRail = NSView()
    private let contentStack = NSStackView()
    private let headerStack = NSStackView()
    private let headerSpinner = NSProgressIndicator()
    private let headerIcon = NSImageView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private let translationScrollView = NSScrollView()
    private let translationTextView = NSTextView()
    private let buttonStack = NSStackView()
    private let copyButton = O48PrimaryButton(frame: .zero)
    private let closeButton = NSButton(title: "", target: nil, action: nil)

    // State
    private var dismissTimer: Timer?
    private var copiedTimer: Timer?
    private var isMouseOver = false
    private var currentTranslation = ""

    private let scrollWidth: CGFloat = 340

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
        // --- Material: the O48 signature. ---
        visualEffectView.blendingMode = .behindWindow
        if cfg.style == "solid" {
            // Opaque, adaptive card — follows the system light/dark appearance.
            visualEffectView.material = .windowBackground
            visualEffectView.state = .inactive
            visualEffectView.appearance = nil
        } else {
            // Focused dark HUD — pinned vibrant-dark so semantic colors resolve light.
            visualEffectView.material = .hudWindow
            visualEffectView.state = .active
            visualEffectView.appearance = NSAppearance(named: .vibrantDark)
        }
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 16
        visualEffectView.layer?.masksToBounds = true

        // --- Leading accent rail. ---
        accentRail.wantsLayer = true
        accentRail.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        accentRail.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(accentRail)
        NSLayoutConstraint.activate([
            accentRail.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            accentRail.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            accentRail.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            accentRail.widthAnchor.constraint(equalToConstant: 3),
        ])

        // --- Content stack. ---
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.edgeInsets = NSEdgeInsets(top: 18, left: 0, bottom: 16, right: 0)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
            contentStack.leadingAnchor.constraint(equalTo: accentRail.trailingAnchor, constant: 18),
            contentStack.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -20),
        ])

        // --- Header: spinner + status glyph + title. ---
        headerSpinner.style = .spinning
        headerSpinner.controlSize = .small
        headerSpinner.isDisplayedWhenStopped = false
        headerSpinner.isHidden = true

        headerIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        headerIcon.contentTintColor = .controlAccentColor

        headerLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .labelColor
        headerLabel.maximumNumberOfLines = 1

        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 6
        headerStack.addArrangedSubview(headerSpinner)
        headerStack.addArrangedSubview(headerIcon)
        headerStack.addArrangedSubview(headerLabel)
        contentStack.addArrangedSubview(headerStack)

        // --- Source (muted, two lines max). ---
        sourceLabel.font = NSFont.systemFont(ofSize: 11)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.maximumNumberOfLines = 2
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.preferredMaxLayoutWidth = scrollWidth
        sourceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        sourceLabel.widthAnchor.constraint(lessThanOrEqualToConstant: scrollWidth).isActive = true
        contentStack.addArrangedSubview(sourceLabel)

        // --- Translation (scrollable, 16pt, comfortable line spacing). ---
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

        // --- Buttons (right-aligned: close, then accent-tinted copy). ---
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

        // --- Hover tracking for keep-on-hover. ---
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
        setHeader(icon: nil, tint: nil, title: StringsLoader["popup.header.translating"], loading: true)
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
        setHeader(icon: "text.bubble.fill", tint: .controlAccentColor, title: StringsLoader["popup.header.result"], loading: false)
        let trimmedSource = truncate(source, max: 400)
        sourceLabel.stringValue = trimmedSource
        sourceLabel.isHidden = trimmedSource.isEmpty
        setBody(translation, color: .labelColor)
        copyButton.attributedTitle = accentTitle(StringsLoader["popup.button.copy"])
        copyButton.isHidden = false
        translationScrollView.contentView.scroll(to: .zero)
        showAndPlace()
        if !isMouseOver { restartDismiss() }
    }

    func showError(message: String) {
        setHeader(icon: "exclamationmark.triangle.fill", tint: .systemOrange, title: StringsLoader["popup.header.error"], loading: false)
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

    private func setHeader(icon name: String?, tint: NSColor?, title: String, loading: Bool) {
        headerLabel.stringValue = title
        if loading {
            headerIcon.isHidden = true
            headerSpinner.isHidden = false
            headerSpinner.startAnimation(nil)
        } else {
            headerSpinner.stopAnimation(nil)
            headerSpinner.isHidden = true
            if let name = name {
                headerIcon.image = NSImage(systemSymbolName: name, accessibilityDescription: title)
                headerIcon.contentTintColor = tint ?? .controlAccentColor
                headerIcon.isHidden = false
            } else {
                headerIcon.isHidden = true
            }
        }
    }

    private func setBody(_ text: String, color: NSColor) {
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16),
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
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: para,
        ])
    }

    // MARK: - Placement / animation

    private func showAndPlace() {
        // Size the window to the current content BEFORE positioning. Content height varies between
        // states (the source line is hidden during loading/error, shown on a result), and AppKit's
        // auto-layout-driven window resize only settles on a later layout pass — reading self.frame
        // before that would mis-anchor the top edge on the loading→result transition. Forcing layout
        // + an explicit setContentSize makes top-center placement exact in every state (the Classic
        // popup sizes explicitly for the same reason).
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

/// Filled-accent "primary" button.
///
/// `NSButton.bezelColor` and default-button (return-key) accent highlighting are both ignored in a
/// non-key panel (`canBecomeKey = false`) and under vibrant appearances like the `.hudWindow` HUD —
/// so a stock accent button renders as a plain gray button indistinguishable from a secondary one.
/// This draws the accent fill on its own layer (with vibrancy disabled) so the primary action always
/// reads as primary, on both the dark HUD (acrylic) and the light card (solid).
private final class O48PrimaryButton: NSButton {
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
        layer?.cornerRadius = 7
        layer?.masksToBounds = true
        applyAccent()
    }

    private func applyAccent() {
        layer?.backgroundColor = NSColor.controlAccentColor.cgColor
    }

    // Keep the accent fill solid rather than vibrancy-blended on the HUD.
    override var allowsVibrancy: Bool { false }

    // Re-resolve the accent cgColor when the system accent / appearance changes.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAccent()
    }

    // Add comfortable horizontal padding and a consistent pill height.
    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 28
        size.height = 24
        return size
    }
}
